%%%----------------------------------------------------------------------
%%% File    : mdb_search.erl
%%% Author  : Nicolas Niclausse <nico@niclux.org>
%%% Purpose : generic server for sending search requests and parsing 
%%%           responses from remote servers 
%%% Created : 10 Aug 2002 by Nicolas Niclausse <nico@niclux.org>
%%%----------------------------------------------------------------------

-module(mdb_search).
-author('nico@niclux.org').
-revision(' $Id$ ').
-vsn(' $Revision$ ').

%%-compile(export_all).
%%-export([Function/Arity, ...]).

-behaviour(gen_server).

%% External exports
-export([start_link/1]).
-export([start_link/0]).
-export([say_slow/4]).
-export([stop/0, search/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([code_change/3]).


-include("mdb.hrl").
-define(tcp_timeout, 10000). % 10sec 
-define(say_sleep, 2000). % 2sec wait between each line to avoid flooding
-define(max_lines, 8). % if more that max_lines to say, say it in private

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:cast(?MODULE, {stop}).

%% asynchronous search
search({Keywords, Input, BotPid, BotName, Params}) ->
    gen_server:cast(?MODULE, {search, Keywords, Input, BotPid, BotName, Params}).

%%%----------------------------------------------------------------------
%%% Callback functions from gen_server
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%%----------------------------------------------------------------------
init(Args) ->
    {ok, #search_state{}}.

%%----------------------------------------------------------------------
%% Func: handle_call/3
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_call(Args, From, State) ->
    {noreply, State}.

%%----------------------------------------------------------------------
%% Func: handle_cast/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_cast({search, Keywords, Input, BotPid, BotName, Params}, State) ->
    case gen_tcp:connect(Params#search_param.server, Params#search_param.port,
                         [list,
                          {packet, line},
                          {active, true}], ?tcp_timeout) of
        {ok, Socket} -> 
            Request = apply(Params#search_param.type, set_request, [Keywords]),
            gen_tcp:send(Socket, Request),
            %% the request is identified by the Socket
            {noreply, State#search_state{requests=[{Socket,
													Input, BotPid , BotName,
													Params#search_param.type, []}
                                                   | State#search_state.requests]}};
        {error, Reason} ->
            say(Input, BotName, 
                atom_to_list(Params#search_param.type) ++ " connection failed",
                BotPid),
            {noreply, State}
    end;

handle_cast({stop}, State) ->
	{stop, normal, State}.

%%----------------------------------------------------------------------
%% Func: handle_info/2
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%%----------------------------------------------------------------------
handle_info({tcp, Socket, Data}, State) ->
    case lists:keysearch(Socket, 1 , State#search_state.requests) of 
        {value, {Socket, Input, BotPid, BotName, Type, Buffer}} ->
            case apply(Type, parse, [Data]) of
                {stop, Result} -> %% stop this connection and say result
                    NewState = remove(Socket, State),
                    say(Input, BotName, Buffer ++ [Result], BotPid),
                    {noreply, NewState};
                {continue, Result} -> %% continue and push string in buffer
                    NewRequests = lists:keyreplace(Socket, 1, State#search_state.requests, {Socket, Input, BotPid, BotName, Type, Buffer ++ [Result]}),
                    {noreply, State#search_state{requests= NewRequests}};
                {say, Result} -> %% say result and continue to read data
                    say(Input, BotName, Buffer ++ [Result], BotPid),
                    {noreply, State};
                {continue} -> %% continue to read
                    {noreply, State};
                {stop} -> %% close connection
                    say(Input, BotName, Buffer, BotPid),
                    NewState = remove(Socket, State),
                    {noreply, NewState}
            end;
        _ ->
            {noreply, State}
    end;

handle_info({tcp_einval, Socket}, State) ->
    {noreply, State};

handle_info({tcp_error, Socket}, State) ->
    NewState = remove(Socket, State),
    {noreply, NewState};

handle_info({tcp_closed, Socket}, State) ->
    NewState = remove(Socket, State),
    {noreply, NewState}.

    
%%----------------------------------------------------------------------
%% Func: terminate/2
%% Purpose: Shutdown the server
%% Returns: any (ignored by gen_server)
%%----------------------------------------------------------------------
terminate(Reason, State) ->
    ok.

%%----------------------------------------------------------------------
%% Func: code_change/3
%%----------------------------------------------------------------------
code_change(OldVsn, State, Extra) ->
    {ok, State}.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: say/4 
%% Purpose: say a string to chan or to private
%%----------------------------------------------------------------------
say(Input, BotName, [], BotPid) ->
    empty;
%% list of strings to say in private, use mdb_behaviours function
say(Input = #data{header_to=BotName}, BotName, Data, BotPid) ->
    spawn_link(?MODULE,say_slow, [Input, BotName, Data, BotPid]);
%%% to much lines, talk in private
say(Input, BotName, Data, BotPid) when length(Data) > ?max_lines ->
    %% set header_to to say it in private
    mdb_bot:say(BotPid, "answer in private"),
    %% spawn a new process to talk in private, with a sleep between each line
    spawn_link(?MODULE,say_slow, [Input#data{header_to=BotName}, BotName, Data, BotPid]);
%%% talk in the channel
say(Input, BotName, Data, BotPid) ->
    mdb_behaviours:say(Input, BotName, Data, BotPid).

%%----------------------------------------------------------------------
%% Func: say_slow/4
%% Purpose: say a list of string with sleep intervals
%%----------------------------------------------------------------------
say_slow(Input, BotName, [], BotPid) ->
    empty;
say_slow(Input, BotName, [String | Data], BotPid) ->
    mdb_behaviours:say(Input, BotName, [String], BotPid),
    timer:sleep(?say_sleep),
    say_slow(Input, BotName, Data, BotPid).

%%----------------------------------------------------------------------
%% Func: remove/2
%% Purpose: remove (and close) Socket entry if found in requests list
%% Returns: new state
%%----------------------------------------------------------------------
remove(Socket, State) ->
    gen_tcp:close(Socket),
    NewList = lists:keydelete(Socket, 1, State#search_state.requests),
    State#search_state{requests = NewList}.