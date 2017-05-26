-module(cpool).

-export([new_pool/3, new_pool_sup/3, get_connection/1, get_connection/2, subscribe/1, pool_spec/3, pool_spec/4]).

new_pool_sup(PoolName, MFA, Opts) ->
    cpool_pool_sup:start_link(PoolName, MFA, Opts).

new_pool(PoolName, MFA, Opts) ->
    supervisor:start_child(cpool_sup, [PoolName, MFA, Opts]).

get_connection(PoolName) ->
    get_connection(PoolName, wait_for_reconnect).

get_connection(PoolName, WaitForReconnect) ->
    cpool_pool_manager:get_connection(PoolName, WaitForReconnect).

subscribe(PoolName) ->
    cpool_pool_manager:subscribe(PoolName).

pool_spec(Name, MFA, PoolOpts) ->
    pool_spec(Name, MFA, PoolOpts, []).

pool_spec(Name, MFA, PoolOpts, Opts) ->
    Shutdown = proplists:get_value(shutdown, Opts, 10000),
    Restart = proplists:get_value(restart, Opts, permanent),
    {Name, {cpool_pool_sup, start_link, [Name, MFA, PoolOpts]}, Restart, Shutdown, supervisor, [cpool_pool_sup]}.
