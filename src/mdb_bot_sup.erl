%%%----------------------------------------------------------------------
%%% File    : mdb_sup.erl
%%% Author  : Dimitri Fontaine <tapoueh@free.fr>
%%% Purpose : Supervise all the bot instances (dynamic)
%%% Created : 19 Feb 2002 by Dimitri Fontaine <tapoueh@free.fr>
%%%----------------------------------------------------------------------

-module(mdb_bot_sup).
-author('tapoueh@free.fr').

-include("mdb.hrl").
-include("config.hrl").

-behaviour(supervisor).

%% External exports
-export([start_link/0, start_child/5]).

%% supervisor callbacks
-export([init/1]).

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Name, Controler, Host, Port, Chan) ->
    supervisor:start_child(?MODULE, [[Name, Controler, Host, Port, Chan]]).

%%%----------------------------------------------------------------------
%%% Callback functions from supervisor
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok,  {SupFlags,  [ChildSpec]}} |
%%          ignore                          |
%%          {error, Reason}   
%%----------------------------------------------------------------------
init([]) ->
    Bot = {manderlbot, {mdb_bot, start_link, []},
	   transient, 2000, worker, [mdb_bot]},

    {ok, {{simple_one_for_one, 3, 60}, [Bot]}}.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------