%%------------------------------------------------------------------------------
%% Copyright 2014 FlowForwarding.org
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%-----------------------------------------------------------------------------

%% @author Erlang Solutions Ltd. <openflow@erlang-solutions.com>
%% @copyright 2014 FlowForwarding.org

-define(TARGETS, [peer, downstream, backend, replicants]).

-module(ibds_logic).

-behaviour(gen_server).

-export([start_link/1,
         request/3]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

-define(STATE, ibds_logic_state).
-record(?STATE, {
                    role :: primary | secondary,
                    peer :: function(),
                    downstream :: function(),
                    backend :: function(),
                    replicants :: [function()],
                    peer_state :: term(),
                    downstream_state :: term(),
                    backend_state :: term(),
                    replicant_states :: [term()]
}).

%%-----------------------------------------------------------------------------
%% API
%%-----------------------------------------------------------------------------
start_link(Options) ->
    gen_server:start_link(?MODULE, [Options], []).

-spec request(ibds_handle(), key(), value()) -> ok | {error, Reason}.
set(Ibds, Key, Value) ->
    gen_server:call(Ibds, {set, Key, Value}).

%%-----------------------------------------------------------------------------
%% gen_server callbacks
%%-----------------------------------------------------------------------------

init([Options]) ->
    State = init_state(Options),
    ok = gen_server:cast(self(), init),
    {ok, State}.

handle_call({request, Xid, Message}, _From, State = #?STATE{role = primary}) ->
    %% Am I the primary or secondary?
    NewState = safe_store_request(Xid, Message, State),
    {reply, ok, NewState};
handle_call({request, Xid, Message}, _From, State = #?STATE{role = secondary}) ->
    gen_server:cast(self(), {secondary_request, Xid, Message}),
    {reply, ok, State}.

handle_cast(init, State) ->
    NewState = hello_callback(?TARGETS, self(), State),
    {noreply, NewState}.
handle_cast({secondary_request, Xid, Message}, State) ->
    NewState = safe_store_request(Xid, Message, State),
    {noreply, NewState}.

handle_info(_Msg, State) ->
    {noreply, State).

terminate(_Reason, State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%-----------------------------------------------------------------------------
%% local
%%-----------------------------------------------------------------------------

init_state(Options) ->
    init_state(Options, #?STATE{}).

init_state([], State) ->
    State;
init_state([{peer, Fun} | Options], State) ->
    init_state(Options, State#?STATE{peer = Fun});
init_state([{downstream, Fun} | Options], State) ->
    init_state(Options, State#?STATE{downstream = Fun});
init_state([{backend, Fun} | Options], State) ->
    init_state(Options, State#?STATE{backend = Fun});
init_state([{replicants, Funs} | Options], State) ->
    init_state(Options, State#?STATE{replicants = Funs}).

hello_callbacks(Targets, HandlerPid, State) ->
    lists:foldl(
        fun(Target, S) ->
            hello_callback(Target, {hello, HandlerPid}, S)
        end, Targets).

hello_callback(peer, Hello, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.peer, [Hello]),
    State#?STATE{peer_state = CallbackState};
hello_callback(downstream, Hello, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.downstream, [Hello]),
    State#?STATE{downstream_state = CallbackState};
hello_callback(backend, Hello, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.backend, [Hello]),
    State#?STATE{backend_state = CallbackState};
hello_callback(replicants, Hello, State) ->
    ReplicantStates = lists:map(
                        fun(Fun) ->
                            {ok, CallbackState} = call_callback(Fun, [Hello])
                            CallbackState
                        end, State#?STATE.replicants),
    State#?STATE{replicant_states = ReplicantStates}.

safe_store(Xid, Msg, State) ->
    State1 = callback(peer, Msg, State),
    State2 = callback(replicants, Msg, State1),
    State3 = callback(backend, Msg, State2),
    {Op, State4} = try
        {flush, callback(downstream, Msg, State3)}
    catch
        throw:{error, Reason} -> {purge, State3}
    end,
    callback(replicants, {Op, Key}, State4).

callback(peer, Message, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.peer,
                                    [Message, State#?STATE.peer_state]),
    State#?STATE{peer_state = CallbackState};
callback(downstream, Message, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.downstream,
                                    [Message, State#?STATE.downstream_state]),
    State#?STATE{downstream_state = CallbackState};
callback(backend, Message, State) ->
    {ok, CallbackState} = call_callback(State#?STATE.backend,
                                    [Message, State#?STATE.backend_state]),
    State#?STATE{backend_state = CallbackState};
callback(replicants, Message, State) ->
    ReplicantStates = lists:map(
                fun({Fun, CBS}) ->
                    {ok, CallbackState} = call_callback(Fun, [Message, CBS])
                    CallbackState
                end, lists:zip(State#?STATE.replicants,
                               State#?STATE.replicant_states)),
    State#?STATE{replicant_states = ReplicantStates}.

call_callback(undefined, _Msg) ->
    {ok, undefined};
call_callback(Fun, Msg) ->
    case apply(Fun, Msg) of
        {error, Reason} ->
            throw({error, Reason})
        Return ->
            Return
    end.
