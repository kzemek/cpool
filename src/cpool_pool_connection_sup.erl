-module(cpool_pool_connection_sup).

-behaviour(supervisor).

-export([start_link/1, init/1]).

start_link(MFA) ->
    supervisor:start_link(?MODULE, MFA).

init(MFA) ->
    Child = {connection, MFA, temporary, 5000, worker, dynamic},
    {ok, {{simple_one_for_one, 5, 60}, [Child]}}.
