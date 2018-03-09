-module(cpool_pool_manager).

-behaviour(gen_server).

-record(state, {
    pool_name,
    connected = 0,
    pool_size,
    stagger,
    backoff,
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
    [] =:= FilteredPids andalso error(no_connections),
    {_, ChosenPid} = lists:min(FilteredPids),
    ChosenPid.

init({PoolName, Supervisor, Opts}) ->
    PoolSize = proplists:get_value(pool_size, Opts, 1),
    Stagger = proplists:get_value(stagger, Opts, 10),
    BackoffMax = proplists:get_value(backoff_max, Opts, 10),
    BackoffStart = proplists:get_value(backoff, Opts, 1),
    Backoff = backoff:type(backoff:init(BackoffStart, BackoffMax), jitter),
    ets:new(PoolName, [protected, named_table, {read_concurrency, true}]),

    schedule_reconnect(0),

    {ok, #state{pool_name = PoolName, pool_size = PoolSize, stagger = Stagger,
                backoff = Backoff, supervisor = Supervisor}}.

handle_call(wait_for_connection, From, State = #state{connected = 0}) ->
    {noreply, State#state{pending = [From | State#state.pending]}};
handle_call(wait_for_connection, _From, State) ->
    {reply, ok, State};
handle_call(_Msg, _From, State) ->
    {reply, {error, bad_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(reconnect, State) ->
    ConnSup = cpool_pool_sup:get_connection_supervisor(State#state.supervisor),
    case catch supervisor:start_child(ConnSup, []) of
        {ok, Pid} ->
            NewState = on_connection_success(Pid, State),
            reconnecting(NewState) andalso schedule_reconnect(State#state.stagger),
            {noreply, NewState};
        _Error ->
            NewBackoff = schedule_reconnect_after_fail(State#state.backoff),
            {noreply, State#state{backoff = NewBackoff}}
    end;
handle_info({'DOWN', _MonitorRef, _Type, Pid, _Info}, State) ->
    ets:delete(State#state.pool_name, Pid),
    reconnecting(State) orelse schedule_reconnect(0),
    {noreply, State#state{connected = State#state.connected - 1}};
handle_info(_, State) ->
    {noreply, State}.

code_change(_, _, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ignore.

on_connection_success(Pid, State) ->
    ets:insert(State#state.pool_name, {Pid}),
    _MonitorRef = erlang:monitor(process, Pid),
    {_, NewBackoff} = backoff:succeed(State#state.backoff),
    (notify_pending(State))#state{pending = [], backoff = NewBackoff,
                                  connected = State#state.connected + 1}.

schedule_reconnect(_After = 0) ->
    self() ! reconnect;
schedule_reconnect(After) when is_integer(After) ->
    erlang:send_after(After, self(), reconnect).

schedule_reconnect_after_fail(Backoff) ->
    Delay = backoff:get(Backoff),
    schedule_reconnect(timer:seconds(Delay)),
    {_, NewBackoff} = backoff:fail(Backoff),
    NewBackoff.

notify_pending(State = #state{pending = Pending}) ->
    [gen_server:reply(From, ok) || From <- Pending],
    State#state{pending = []}.

reconnecting(#state{connected = Connected, pool_size = PoolSize}) ->
    Connected < PoolSize.

