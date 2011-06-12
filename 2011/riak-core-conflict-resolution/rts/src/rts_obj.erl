%% @doc A suite of functions that operate on the algebraic data type
%% `rts_obj'.
%%
%% TODO Possibly move type/record defs in there and use accessor funs
%% and opaque types.
-module(rts_obj).
-export([ancestors/1, children/1, equal/1, equal/2, merge/1, unique/1,
         update/3]).
-export([meta/1, val/1, vclock/1]).

-include("rts.hrl").

%% @pure
%%
%% @doc Given a list of `rts_obj()' return a list of all the
%% ancesotrs.  Ancestors are objects that all the other objects in the
%% list have descent from.
-spec ancestors([rts_obj()]) -> [rts_obj()].
ancestors(Objs0) ->
    Objs = [O || O <- Objs0, O /= not_found],
    As = [[O2 || O2 <- Objs,
                 ancestor(O2#rts_vclock.vclock,
                          O1#rts_vclock.vclock)] || O1 <- Objs],
    unique(lists:flatten(As)).

%% @pure
%%
%% @doc Predicate to determine if `Va' is ancestor of `Vb'.
-spec ancestor(vclock:vclock(), vclock:vclock()) -> boolean().
ancestor(Va, Vb) ->
    vclock:descends(Vb, Va) andalso (vclock:descends(Va, Vb) == false).

%% @pure
%%
%% @doc Given a list of `rts_obj()' return a list of the children
%% objects.  Children are the descendants of all others objects.
children(Objs) ->
    unique(Objs) -- ancestors(Objs).

%% @pure
%%
%% @doc Predeicate to determine if `ObjA' and `ObjB' are equal.
-spec equal(ObjA::rts_obj(), ObjB::rts_obj()) -> boolean().
equal(#rts_vclock{vclock=A}, #rts_vclock{vclock=B}) -> vclock:equal(A,B);

equal(#rts_basic{val=V}, #rts_basic{val=V}) -> true;

equal(#rts_sbox{val=A}, #rts_sbox{val=B}) ->
    statebox:value(A) == statebox:value(B);

equal(not_found, not_found) -> true;

equal(_, _) -> false.

%% @pure
%%
%% @doc Closure around `equal/2' for use with HOFs (damn verbose
%% Erlang).
-spec equal(ObjA::rts_obj()) -> fun((ObjB::rts_obj()) -> boolean()).
equal(ObjA) ->
    fun(ObjB) -> equal(ObjA, ObjB) end.

%% @pure
%%
%% @doc Merge the list of `Objs', calling the appropriate reconcile
%% fun if there are siblings.
-spec merge([rts_obj()]) -> rts_obj().
merge([not_found|_]=Objs) ->
    P = fun(X) -> X == not_found end,
    case lists:all(P, Objs) of
        true -> not_found;
        false -> merge(lists:dropwhile(P, Objs))
    end;

merge([#rts_basic{}|_]=Objs) ->
    case unique(Objs) of
        [] -> not_found;
        [Obj] -> Obj;
        Mult -> 
            {M,F} = proplists:get_value(rec_mf, meta(hd(Mult))),
            M:F(Mult)
    end;

merge([#rts_vclock{}|_]=Objs) ->
    case rts_obj:children(Objs) of
        [] -> not_found;
        [Child] -> Child;
        Chldrn ->
            Val = rts_get_fsm:reconcile(lists:map(fun val/1, Chldrn)),
            MergedVC = vclock:merge(lists:map(fun vclock/1, Chldrn)),
            #rts_vclock{val=Val, vclock=MergedVC}
    end;

merge([#rts_sbox{}|_]=Objs) ->
    SBs = [O#rts_sbox.val || O <- Objs],
    S = statebox:merge(SBs),
    #rts_sbox{val=S}.

%% @pure
%%
%% @doc Given a list of `Objs' return the list of uniques.
-spec unique([rts_obj()]) -> [rts_obj()].
unique(Objs) ->
    F = fun(not_found, Acc) ->
                Acc;
           (Obj, Acc) ->
                case lists:any(equal(Obj), Acc) of
                    true -> Acc;
                    false -> [Obj|Acc]
                end
        end,
    lists:foldl(F, [], Objs).

%% @pure
%%
%% @doc Given a `Val' update the `Obj'.  The `Updater' is the name of
%% the entity performing the update.x
%%
%% TODO Do I want to limit `Updater' to `node()'?
-spec update(val(), node(), rts_obj()) -> rts_obj().
update(Val, _Updater, #rts_basic{}=Obj0) ->
    Obj0#rts_basic{val=Val};

update(Val, Updater, #rts_vclock{vclock=VClock0}=Obj0) ->
    VClock = vclock:increment(Updater, VClock0),
    Obj0#rts_vclock{val=Val, vclock=VClock}.

-spec meta(rts_obj()) -> meta().
meta(#rts_basic{meta=Meta}) -> Meta;
meta(#rts_vclock{meta=Meta}) -> Meta.

-spec val(rts_obj()) -> any().
val(#rts_basic{val=Val}) -> Val;
val(#rts_vclock{val=Val}) -> Val;
val(#rts_sbox{val=SB}) -> statebox:value(SB);
val(not_found) -> not_found.

%% @pure
%%
%% @doc Given a vclock type `Obj' retrieve the vclock.
-spec vclock(rts_vclock()) -> vclock:vclock().
vclock(#rts_vclock{vclock=VC}) -> VC.
