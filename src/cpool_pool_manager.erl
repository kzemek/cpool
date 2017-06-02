-module(cpool_pool_manager).

-behaviour(gen_server).

-record(state, {
    pool_name,
    conns = #{},
    supervisor,
    pending = []
}).

-export([start_link/3, get_connection/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

start_link(PoolName, Supervisor, Opts) ->
    gen_server:start_link({local, PoolName}, ?MODULE, {PoolName, Supervisor, Opts}, []).

get_connection(PoolName, wait_for_reconnect) ->
    case ets:tab2list(PoolName) of
        [] -> gen_server:call(PoolName, wait_for_connection);
        _ -> ok
    end,
    get_connection(PoolName, no_wait_for_reconnect);
get_connection(PoolName, no_wait_for_reconnect) ->
    AllPids = ets:tab2list(PoolName),
    FilteredPids = lists:filtermap(
            fun({Pid}) ->
                case process_info(Pid, message_queue_len) of
                    undefined -> false;
                    {message_queue_len, X} -> {true, {X, Pid}}
                end
            end,
            AllPids),
    {_, ChosenPid} = lists:min(FilteredPids),
    ChosenPid.

init({PoolName, Supervisor, Opts}) ->
    ConnsNum = proplists:get_value(pool_size, Opts, 1),
    BackoffMax = proplists:get_value(backoff_max, Opts, 10),
    BackoffStart = proplists:get_value(backoff, Opts, 1),

    Backoff = backoff:type(backoff:init(BackoffStart, BackoffMax), jitter),
    ets:new(PoolName, [public, named_table, {read_concurrency, true}]),

    [self() ! {reconnect, Backoff} || _ <- lists:seq(1, ConnsNum)],
    {ok, #state{pool_name = PoolName, supervisor = Supervisor}}.

handle_call(wait_for_connection, From, State) ->
    case maps:size(State#state.conns) of
        0 -> {noreply, State#state{pending = [From | State#state.pending]}};
        _ -> {reply, ok, State}
    end;
handle_call(_Msg, _From, State) ->
    {reply, {error, bad_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({reconnect, Backoff}, State) ->
    ConnSup = cpool_pool_sup:get_connection_supervisor(State#state.supervisor),
    case catch supervisor:start_child(ConnSup, []) of
        {ok, Pid} ->
            _MonitorRef = erlang:monitor(process, Pid),
            {_, NewBackoff} = backoff:succeed(Backoff),
            NewConns = maps:put(Pid, NewBackoff, State#state.conns),
            ets:insert(State#state.pool_name, {Pid}),
            {noreply, NewState#state{conns = NewConns}};
        _Error ->
            schedule_reconnect(Backoff),
            {noreply, State}
    end;
handle_info({'DOWN', _MonitorRef, _Type, Pid, _Info}, State) ->
    ets:delete(State#state.pool_name, Pid),
    Backoff = maps:get(Pid, NewState#state.conns),
    NewConns = maps:remove(Pid, NewState#state.conns),
    schedule_reconnect(Backoff),
    {noreply, NewState#state{conns = NewConns}};
handle_info(_, State) ->
    {noreply, State}.

code_change(_, _, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ignore.

schedule_reconnect(Backoff) ->
    Delay = backoff:get(Backoff),
    {_, NewBackoff} = backoff:fail(Backoff),
    erlang:send_after(timer:seconds(Delay), self(), {reconnect, NewBackoff}).

