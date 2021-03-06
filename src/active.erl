-module(active).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-record(state, {last, root}).
-export([start_link/0, on_compile/2, init/1, handle_call/3,
         handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() -> gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    fs:subscribe(),
    erlang:process_flag(priority, low),
    gen_server:cast(self(), recompile_all),
    {ok, #state{last=fresh, root=fs:path()}}.

handle_call(_Request, _From, State) -> {reply, ok, State}.
handle_cast(recompile_all, State) -> compile(top(), ["all"]), {noreply, State}.
handle_info({_Pid, {fs,file_event}, {Path, Flags}}, #state{root=Root} = State) ->
    %mad:info("Path info: ~p~n", [Path]),
    Cur = path_shorten(filename:split(Root)),
    P = filename:split(Path),
    Result = case lists:prefix(Cur, P) of
        true -> path_event(P -- Cur, Flags, State);
        false -> ok
    end,

    {noreply, State#state{last={event, Path, Flags, Result}}};

handle_info({load_ebin, Atom}, State) ->
    do_load_ebin(Atom),
    {noreply, State#state{last={do_load_ebin, Atom}}};

handle_info(Info, State) -> {noreply, State#state{last={unk, Info}}}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

path_event(C, [E|_Events], _State) when E =:= created; E =:= modified; E =:= renamed ->
    case path_filter(C) of true -> maybe_otp(C); false -> ignore end;
path_event(C, [_E|Events], State) -> path_event(C, Events, State);
path_event(_, [], _State) -> done.

maybe_otp(C) ->
    case application:get_env(active, handler) of
         {ok,{M,F}} -> M:F(C);
                  _ -> otp(C) end.

otp(["deps",App|Rest]) -> maybe_app(App,Rest);
otp(["apps",App|Rest]) -> maybe_app(App,Rest);
otp([Some|Path]) -> maybe_app(top(),[Some|Path]);
otp(_) -> ok.

maybe_app(App, Path) ->
    EnabledApps = application:get_env(active, apps, undefined),
    case EnabledApps of
        undefined -> app(App, Path);
        {ok,L} when is_list(L) ->
            AppAtom = list_to_atom(App),
            case lists:member(AppAtom, L) of
                true -> app(App, Path);
                false -> skip
            end
    end.

app( App,["ebin",Module|_])     -> load_ebin(App,Module);
app(_App,["priv","fdlink"++_])  -> skip;
app(_App,["priv","mac"++_])     -> skip;
app(_App,["priv","windows"++_]) -> skip;
app(_App,["priv","linux"++_])   -> skip;
app(_App,["priv","static"|_Rest])   -> compile_skip(compile_on_static,_App,_Rest);
app( App,["priv"|Rest])             -> compile_skip(compile_on_priv,App,Rest);
app( App,["include"|Rest])      -> compile(App,Rest);
app( App,["src"|Rest])          -> compile(App,Rest);
app(_App,["psbin",Module|_])    -> mad:info("Active: module loaded: ~p~n\n\r",[Module]),skip;
app(_,_)-> ok.

compile_skip(Key,App,Rest) -> case application:get_env(active,Key,false) of
                                            false -> skip;
                                            _ -> compile(App,Rest) end.

top() -> lists:last(filename:split(fs:path())).

on_compile(_App, _Rest) -> ok.

compile(_App, []) -> ok;
compile(App,Rest) ->
    case application:get_env(active,on_compile,{?MODULE,on_compile}) of
         {MOD,FUN} -> MOD:FUN(App,Rest);
         _ -> ok end,
    case lists:last(Rest) of
         ".#" ++ _ -> skip;
             _ -> try put(App,updated),
                      mad_compile:compile(App)
                catch E:R ->
                      mad:info("~p", [erlang:get_stacktrace()]),
                      mad:info("Catch: ~p:~p",[E,R]) end end.

load_ebin(_App, EName) ->
    case lists:reverse(EName) of
        "maeb." ++ Tail -> Name = lists:reverse(Tail),
            LoadRes = do_load_ebin(list_to_atom(lists:flatten(Name))),
            mad:info("Active: module loaded: ~p~n\n\r", [LoadRes]),
            active_events:notify_reload(LoadRes);
        "#aeb." ++ _ -> ok;
        _ -> mad:info("Active: unknown BEAM file: ~p", [EName]), ok
    end.

do_load_ebin(Module) ->
    IsLoaded = case code:is_loaded(Module) of
                   {file, _} ->
                       true;
                   false ->
                       false
               end,
    {Module, Binary, Filename} = code:get_object_code(Module),
    case code:load_binary(Module, Filename, Binary) of
        {module, Module} when IsLoaded->
            {reloaded, Module};
        {module, Module} when not IsLoaded ->
            {loaded_new, Module};
        {error, Reason} ->
            {load_error, Module, Reason}
    end.

% ["a", "b", ".."] -> ["a"]
path_shorten(Coms) -> path_shorten_r(lists:reverse(Coms), [], 0).

path_shorten_r([".."|Rest], Acc, Count) -> path_shorten_r(Rest, Acc, Count + 1);
path_shorten_r(["."|Rest], Acc, Count) -> path_shorten_r(Rest, Acc, Count);
path_shorten_r([_C|Rest], Acc, Count) when Count > 0 -> path_shorten_r(Rest, Acc, Count - 1);
path_shorten_r([C|Rest], Acc, 0) -> path_shorten_r(Rest, [C|Acc], 0);
path_shorten_r([], Acc, _) -> Acc.

path_filter(L) ->
    not lists:any(fun(E) -> not path_filter_dir(E) end, L)
        andalso path_filter_file(lists:last(L))
        andalso path_filter_ext(ext(L)).

ext(L) -> filename:extension(lists:last(L)).

path_filter_dir(".git") -> false;
path_filter_dir(".hg")  -> false;
path_filter_dir(".svn") -> false;
path_filter_dir("CVS")  -> false;
path_filter_dir("log")  -> false;
path_filter_dir("node_modules")  -> false;
path_filter_dir(_)      -> true.

path_filter_file(".rebarinfo")     -> false;   % new rebars
path_filter_file("LICENSE")        -> false;
path_filter_file("4913 (deleted)") -> false;   % vim magical file
path_filter_file("4913")           -> false;
path_filter_file(_)                -> true.

path_filter_ext(".app")            -> false;
path_filter_ext(".jpg")            -> false;
path_filter_ext(".png")            -> false;
path_filter_ext(".gif")            -> false;
path_filter_ext(".json")           -> false;
path_filter_ext(".js")             -> false;
path_filter_ext(_)                 -> true.
