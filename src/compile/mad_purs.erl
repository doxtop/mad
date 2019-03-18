-module(mad_purs).
-compile(export_all).

opt(Conf) -> mad_utils:get_value(purs_opts, Conf, []).

compile(File,_Inc,Bin,Conf,Def) ->
    mad:info("==> Compile: ~p deferred:~p~n", [File, Def]),
    DepsDir = mad_utils:get_value(deps_dir, Conf, ["deps"]),
    Opt = opt(Conf),
    Compiler= mad_utils:get_value(compiler, Opt, "purs"),
    Bin1    = mad_utils:get_value(purs_out, Opt, Bin),
    Bin2    = mad_utils:get_value(js_out,   Opt, Bin),
    NS      = mad_utils:get_value(namespace,Opt, "purescript-*"),
    Entry   = filename:basename(File, ".purs"),
    DefE    = filename:basename(Def, ".purs"),
    Bundle  = filename:join([Bin2, case Def of [] -> Entry ++ ".js"; _ -> DefE ++ ".js" end]),
    Main    = mad_utils:get_value(main, Opt, []),
    Bundler = Compiler,

    case sh:oneliner(io_lib:format("~s --version", [Compiler])) of
        {_,0,Ver} ->
        Compile = lists:filter(fun([]) -> false; (_) -> true end,
            [atom_to_list(Compiler), "compile", File, Def, filename:join([DepsDir, NS, "src", "**", "*.purs"]), "-o", Bin1]),

        case sh:oneliner(Compile) of
            {_,0,R} when Main =:= Entry orelse Main =:= DefE ->
                case sh:oneliner([atom_to_list(Bundler), "bundle", filename:join([Bin1, "**", "*.js"]), "-m", Entry, "--main", Main, "-o", Bundle]) of
                    {_,0,_} -> mad:info("~s to ~p with ~s-~s ~n", [R, Bundle, Compiler, Ver]), false;
                    {_,_,_R1} -> false
                end;
            {_,0,_R} -> false; % nothing to compile
            {_,_,R} ->
                case binary:matches(R, [<<"Module ">>,<<" was not found">>], []) of
                    [{S1,L1},{S2,_}|_] ->
                        Mod = binary:part(R,S1+L1,S2-S1-L1),
                        {postpone, Mod};
                    _ -> mad:info("Error ~s~n",[format(R)]), true
                end
        end;
        {_,_,R} -> mad:info("Compiler not installed: ~p~n", [R]), true end.

format(E) -> 
    case binary:matches(E, [<<"Error found:">>, <<" unable to parse module: ">>], []) of 
        [{S1,L1}] -> binary:part(E,S1+L1,byte_size(E)-L1);
        Pe -> Pe
    end.