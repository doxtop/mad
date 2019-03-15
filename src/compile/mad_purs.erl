-module(mad_purs).
-compile(export_all).

opt(Conf) -> mad_utils:get_value(purs_opts, Conf, []).

compile(File,_Inc,Bin,Conf,Deps) ->
    mad:info("==>Compile: ~p Dep:~p~n", [File, Deps]),
    DepsDir = mad_utils:get_value(deps_dir, Conf, ["deps"]),
    Opt = opt(Conf),
    Compiler= mad_utils:get_value(compiler, Opt, "purs"),
    Bin1    = mad_utils:get_value(purs_out, Opt, Bin),
    Bin2    = mad_utils:get_value(js_out,   Opt, Bin),
    NS      = mad_utils:get_value(namespace,Opt, "purescript-*"),
    Entry   = filename:basename(File, ".purs"),
    DepE    = filename:basename(Deps, ".purs"),
    Bundle  = filename:join([Bin2, Entry ++ ".js"]),
    Main    = mad_utils:get_value(main, Opt, []),
    Bundler = Compiler,

    case sh:oneliner(io_lib:format("~s --version", [Compiler])) of 
        {_,0,Ver} ->
        Line = case Deps of [] -> 
            [atom_to_list(Compiler), "compile", File, filename:join([DepsDir, NS, "src", "**", "*.purs"]), "-o", Bin1];
            M when Deps =/= File -> [atom_to_list(Compiler), "compile", File, M, filename:join([DepsDir, NS, "src", "**", "*.purs"]), "-o", Bin1];
            _->[atom_to_list(Compiler), "compile", File, filename:join([DepsDir, NS, "src", "**", "*.purs"]), "-o", Bin1] end,

        mad:info("Run: ~p~n", [Line]),
        case sh:oneliner(Line) of
            {_,0,R} when Main =:= Entry orelse Main =:= DepE ->
                case sh:oneliner([atom_to_list(Bundler), "bundle", filename:join([Bin1, "**", "*.js"]), "-m", Entry, "--main", Main, "-o", Bundle]) of
                    {_,0,_} -> mad:info("~s to ~p with ~s-~s ~n", [R, Bundle, Compiler, Ver]), false;
                    {_,_,_R1} -> false
                end;
            {_,0,R} -> false; % nothing to compile
            {_,_,R} -> 
                mad:info("compilation error: ~p~n", [R]), 
                ModuleNotFound = lists:any(fun(E) ->
                case binary:split(E, [<<"Module ">>, <<" was not found.">>], [global, trim_all]) of 
                    [_,Mod|_] -> true;
                    _ -> false
                end end, binary:split(R, [<<"Error ">>], [global,trim_all])),
                if ModuleNotFound =:= true ->
                    {postpone, filename:basename(File)}; % full path is actually ignored
                true -> true end
        end;
        {_,_,R} -> mad:info("Compiler not installed: ~p~n", [R]), true end.
