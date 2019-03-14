-module(mad_purs).
-compile(export_all).

opt(Conf) -> mad_utils:get_value(purs_opts, Conf, []).

compile(File,_Inc,Bin,Conf,_Deps) ->
    DepsDir = mad_utils:get_value(deps_dir, Conf, ["deps"]),
    Opt = opt(Conf),
    Compiler= mad_utils:get_value(compiler, Opt, "purs"),
    Bin1    = mad_utils:get_value(purs_out, Opt, Bin),
    Bin2    = mad_utils:get_value(js_out,   Opt, Bin),
    NS      = mad_utils:get_value(namespace,Opt, "purescript-*"),
    Entry   = filename:basename(File, ".purs"),
    Bundle  = filename:join([Bin2, Entry ++ ".js"]),
    Main    = mad_utils:get_value(main, Opt, []),
    Bundler = Compiler,

    case sh:oneliner(io_lib:format("~s --version", [Compiler])) of 
        {_,0,Ver} ->
        case sh:oneliner([atom_to_list(Compiler), "compile", File, filename:join([DepsDir, NS, "src", "**", "*.purs"]), "-o", Bin1]) of
            {_,0,<<>>} -> false; % nothing new to compile
            {_,0,R} when Main =:= Entry ->
                case sh:oneliner([atom_to_list(Bundler), "bundle", filename:join([Bin1, "**", "*.js"]), "-m", Entry, "--main", Main, "-o", Bundle]) of
                    {_,0,_} -> mad:info("~s to ~p with ~s-~s ~n", [R, Bundle, Compiler, Ver]), false;
                    {_,_,_R1} -> false
                end;
            {_,0,_} -> false; % nothing to bundle
            {_,_,R} -> mad:info("Compilation failed: ~p~n", [R]), true
        end;
        {_,_,R} -> mad:info("Compiler not installed: ~p~n", [R]), true end.
