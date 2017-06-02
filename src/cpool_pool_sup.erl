-module(cpool_pool_sup).

-behaviour(supervisor).

-export([start_link/3, init/1, get_connection_supervisor/1]).

start_link(PoolName, MFA, Opts) ->
    supervisor:start_link(?MODULE, {PoolName, MFA, Opts}).

init({PoolName, MFA, Opts}) ->
    PoolManager = cpool_pool_manager,
    ConnectionSup = cpool_pool_connection_sup,
    Children = [
        {ConnectionSup, {ConnectionSup, start_link, [MFA]}, permanent, 5000, supervisor, [ConnectionSup]},
        {PoolManager, {PoolManager, start_link, [PoolName, self(), Opts]}, permanent, 5000, worker, [PoolManager]}
    ],
    {ok, {{one_for_all, 5, 60}, Children}}.

get_connection_supervisor(Sup) ->
    Children = supervisor:which_children(Sup),
    {_, ConnSup, _, _} = lists:keyfind(cpool_pool_connection_sup, 1, Children),
    ConnSup.
