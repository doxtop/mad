-module(mad_erl).
-copyright('Sina Samavati').
-compile(export_all).
-define(COMPILE_OPTS(Inc, Ebin, Opts, Deps),
    compile_options() ++ [{i, [Inc]}, {outdir, Ebin}] ++ Opts ++ Deps).

compile_options() -> application:get_env(mad,compile_options,
    [return_errors, return_warnings, debug_info, nowarn_export_all]).
erl_to_beam(Bin, F) -> filename:join(Bin, filename:basename(F, ".erl") ++ ".beam").

filter(I) -> [ X || X <- I, X /= warnings_as_errors, X /= warn_export_all, X /=warn_unused_import] .

opt(Conf) -> mad_utils:get_value(erl_opts, Conf, []).

compile(File,Inc,Bin,Conf,Deps) ->
    BeamFile = erl_to_beam(Bin, File),
    Compiled = mad_compile:is_compiled(BeamFile, File),
    if  Compiled =:= false ->
        Opts1 = ?COMPILE_OPTS(Inc, Bin, opt(Conf), Deps),
%  VERBOSE
%        mad:info("Compiling ~s~n", [File -- mad_utils:cwd()]),
        NewCompile = compile:file(File, filter(Opts1)),
        ret(NewCompile);
    true -> false end.

ret(error) -> true;
ret({error,X}) -> lines(error,X);
ret({error,X,_}) -> lines(error,X);
ret({ok,_}) -> false;
ret({ok,_,[]}) -> false;
ret({ok,_,X}) -> lines(warning,X), false;
ret({ok,_,X,_}) -> lines(warning,X), false.

lines(Tag,X) ->
    S=case file:get_cwd() of {ok,Cwd} -> length(Cwd); _ -> 0 end,
    [[ mad:info("Line ~p: ~p ~p in ~p~n",[ L,Tag,R,lists:nthtail(S,F) ]) || {L,_,R} <- E ] || {F,E} <- X ], true.
