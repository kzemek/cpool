%%%-------------------------------------------------------------------
%% @doc cpool top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(cpool_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    Child = {cpool_pool_sup, {cpool_pool_sup, start_link, []}, temporary, 10000, supervisor, [cpool_pool_sup]},
    {ok, {{simple_one_for_one, 0, 1}, [Child]}}.

%%====================================================================
%% Internal functions
%%====================================================================
