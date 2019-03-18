-module(active_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).
-define(CHILD(I, Type, Args), {I, {I, start_link, Args}, permanent, 5000, Type, [I]}).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).
init([]) -> {ok, { {one_for_one, 5, 10}, [ ?CHILD(active, worker, []),
                                           ?CHILD(active_events, worker, []) ]}}.

