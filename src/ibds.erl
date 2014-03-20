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

%% @doc
%% Provides an API to set and delete data in a replicated data store.  An
%% primary/secondary pair provide for immediately failover.  Remote
%% replicants provide for recovery from more catastrophic failures.
%%
%% repl_fun/1 takes the tuple {hello, Role, HandlerPid} where Role
%% is primary or secondary. repl_fun/2 takes
%% the tuples {Xid, Msg} and the State variable.
%% Replicants also receive {flush, Xid} and
%% {purge, Xid}.  repl_fun/1 and repl_fun/2 should return {ok, State}
%% for success or {error, Reason, State} for failure.  If The callback
%% code relies on a process, it should monitor HandlerPid and exit when
%% HandlerPid exits.
%% @end

-module(ibds).

-export([open/1,
         set/3,
         delete/2]).

-type ibds_handle() :: term().
-type repl_fun() :: function().
-type option() :: {peer, repl_fun()} |
                  {downstream, repl_fun()} |
                  {backend, repl_fun()} |
                  {replicants, [repl_fun()]}.
-type options() :: [option()].
-type key() :: atom().
-type value() :: term().

%% @doc
%% Open an existing or create a new ibds data store.
%% Calls repl_fun/3 for peer, downstream, and replicants with the
%% hello request.  Elects a primary.
%% @end
-spec open(options()) -> {ok, ibds_handle()} | {error, Reason :: term()}.
open(Name, Options) ->
    ibds_sup:start_child(Options).

%% @doc
%% Process a request.  Calls repl_fun/3 for peer, downstream,
%% and replicants with the set request.
%% @end
-spec request(ibds_handle(), xid(), message()) -> ok | {error, Reason}.
request(Ibds, Xid, Message) ->
    ibds_logic:request(Ibds, Xid, Message).
