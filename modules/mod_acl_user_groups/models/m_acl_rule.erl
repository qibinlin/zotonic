%% @author Arjan Scherpenisse <marc@worrell.nl>
%% @copyright 2015 Arjan Scherpenisse
%% Date: 2015-03-09
%%
%% @doc Access to the ACL rules

%% Copyright 2015 Arjan Scherpenisse
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

-module(m_acl_rule).
-author("Arjan Scherpenisse <marc@worrell.nl").

-behaviour(gen_model).

%% interface functions
-export(
   [
    m_find_value/3,
    m_to_list/2,
    m_value/2,

    is_valid_code/2,

    manage_schema/2,
    all_rules/3,

    update/4,
    insert/3,
    delete/3,

    revert/2,
    publish/2,

    ids_to_names/2,
    import_rules/2
   ]).

-include_lib("zotonic.hrl").

-define(valid_acl_kind(T), ((T) =:= rsc orelse (T) =:= module)).
-define(valid_acl_state(T), ((T) =:= edit orelse (T) =:= publish)).


%% @doc Fetch the value for the key from a model source
%% @spec m_find_value(Key, Source, Context) -> term()
m_find_value(is_valid_code, #m{value=undefined} = M, _Context) ->
    M#m{value=is_valid_code};
m_find_value(Code, #m{value=is_valid_code}, Context) ->
    is_valid_code(Code, Context);
m_find_value(generate_code, #m{value=undefined}, Context) ->
    generate_code(Context);

m_find_value(default_upload_size, #m{value=undefined}, _Context) ->
    acl_user_groups_checks:max_upload_size_default();
m_find_value(upload_size, #m{value=undefined}, Context) ->
    acl_user_groups_checks:max_upload_size(Context);

m_find_value(can_insert, #m{value=undefined} = M, _Context) ->
    M#m{value=can_insert};
m_find_value(ContentGroupId, #m{value=can_insert} = M, _Context) ->
    M#m{value={can_insert, ContentGroupId}};
m_find_value(CategoryId, #m{value={can_insert, none}}, Context) ->
    acl_user_groups_checks:can_insert_category(CategoryId, Context);
m_find_value(CategoryId, #m{value={can_insert, ContentGroupId}}, Context) ->
    acl_user_groups_checks:can_insert_category(ContentGroupId, CategoryId, Context);

m_find_value(can_move, #m{value=undefined} = M, _Context) ->
    M#m{value=can_move};
m_find_value(ContentGroupId, #m{value=can_move} = M, _Context) ->
    M#m{value={can_move, ContentGroupId}};
m_find_value(RscId, #m{value={can_move, ContentGroupId}}, Context) ->
    acl_user_groups_checks:can_move(ContentGroupId, RscId, Context);

m_find_value(T, M=#m{value=undefined}, _Context) when ?valid_acl_kind(T) ->
    M#m{value=T};
m_find_value(actions, #m{value=T}, Context) when ?valid_acl_kind(T) ->
    actions(T, Context);
m_find_value(S, M=#m{value=T}, _) when ?valid_acl_kind(T), ?valid_acl_state(S) ->
    M#m{value={list, T, S}};
m_find_value({all, Opts}, #m{value={list, T, S}}, Context) ->
    all_rules(T, S, Opts, Context).


%% @spec m_to_list(Source, Context) -> List
m_to_list(_, _Context) ->
    [].

%% @spec m_value(Source, Context) -> term()
m_value(#m{value=undefined}, _Context) ->
    undefined.


%% @doc Generate a code for testing out the 'test' acl rules
generate_code(Context) ->
    case z_acl:is_allowed(use, mod_acl_user_groups, Context) of
        true ->
            z_utils:pickle({acl_test, calendar:universal_time()}, Context);
        false ->
            undefined
    end.

is_valid_code(Code, Context) ->
    try
        {acl_test, DT} = z_utils:depickle(Code, Context),
        calendar:universal_time() < z_datetime:next_day(DT)
    catch
        _:_ ->
            false
    end.


-type acl_rule() :: list().
-spec all_rules(rsc | module, edit | publish, #context{}) -> [acl_rule()].
all_rules(Kind, State, Context) ->
    all_rules(Kind, State, [], Context).

-type acl_rules_opt() :: {group, string()}.
-spec all_rules(rsc | module, edit | publish, [acl_rules_opt()], #context{}) -> [acl_rule()].
all_rules(Kind, State, Opts, Context) ->
    Query = "SELECT * FROM " ++ z_convert:to_list(table(Kind)) 
        ++ " WHERE " ++ state_sql_clause(State),
    All = z_db:assoc(Query, Context),
    sort_by_user_group(normalize_actions(All), z_convert:to_integer(proplists:get_value(group, Opts)), Context).

sort_by_user_group(Rs, undefined, Context) ->
    Tree = m_hierarchy:menu(acl_user_group, Context),
    Ids = lists:reverse(flatten_tree(Tree, [])),
    Zipped = lists:zip(Ids, lists:seq(1,length(Ids))),
    WithNr = lists:map(fun(R) ->
                               UGId = proplists:get_value(acl_user_group_id, R),
                               Nr = proplists:get_value(UGId, Zipped),
                               IsBlock = proplists:get_value(is_block, R),
                               {{Nr,not IsBlock}, R}
                       end,
                       Rs),
    Rs1 = lists:sort(WithNr),
    [ R1 || {_,R1} <- Rs1 ];

sort_by_user_group(Rs, Group, Context) ->
    Parents = m_hierarchy:parents(acl_user_group, Group, Context),
    Tree = m_hierarchy:menu(acl_user_group, Context),
    Ids = [Group | Parents] ++ lists:reverse(flatten_tree(Tree, [])),
    Zipped = lists:zip(Ids, lists:seq(1,length(Ids))),
    WithNr = lists:map(fun(R) ->
                               UGId = proplists:get_value(acl_user_group_id, R),
                               Nr = proplists:get_value(UGId, Zipped),
                               IsBlock = proplists:get_value(is_block, R),
                               {{Nr,not IsBlock}, R}
                       end,
                       Rs),
    Rs1 = lists:sort(WithNr),
    [ R1 || {_,R1} <- Rs1 ].


flatten_tree([], Acc) ->
    Acc;
flatten_tree([{Id,Sub}|Rest], Acc) ->
    Acc1 = flatten_tree(Sub, [Id|Acc]),
    flatten_tree(Rest, Acc1).

table(rsc) -> acl_rule_rsc;
table(module) -> acl_rule_module.

state_sql_clause(edit) -> "is_edit = true";
state_sql_clause(publish) -> "is_edit = false".

normalize_actions(Rows) ->
    [normalize_action(Row) || Row <- Rows].

normalize_action(Row) ->
    Actions = proplists:get_value(actions, Row),
    [{actions, [{z_convert:to_atom(T), true} || T <- string:tokens(z_convert:to_list(Actions), ",")]}
     | proplists:delete(actions, Row)].

actions(rsc, Context) ->
    [
     {view, ?__("view (acl action)", Context)},
     {insert, ?__("insert (acl action)", Context)},
     {update, ?__("edit (acl action)", Context)},
     {delete, ?__("delete (acl action)", Context)},
     {link, ?__("link (acl action)", Context)}
    ];
actions(module, Context) ->
    [
     {use, ?__("use (acl action)", Context)}
    ].


update(Kind, Id, Props, Context) ->
    lager:info("[~p] ACL user groups update by ~p of ~p:~p with ~p",
               [z_context:site(Context), z_acl:user(Context), Kind, Id, Props]),
    Result = z_db:update(
               table(Kind), Id,
               [{is_edit, true},
                {modifier_id, z_acl:user(Context)},
                {modified, calendar:universal_time()}
                | Props], Context
              ),
    mod_acl_user_groups:rebuild(edit, Context),
    Result.

insert(Kind, Props, Context) ->
    lager:info("[~p] ACL user groups insert by ~p of ~p with ~p",
               [z_context:site(Context), z_acl:user(Context), Kind, Props]),
    Result = z_db:insert(
               table(Kind),
               [{is_edit, true},
                {modifier_id, z_acl:user(Context)},
                {modified, calendar:universal_time()},
                {creator_id, z_acl:user(Context)},
                {created, calendar:universal_time()} | Props], Context
              ),
    mod_acl_user_groups:rebuild(edit, Context),
    Result.

delete(Kind, Id, Context) ->
    lager:info("[~p] ACL user groups delete by ~p of ~p:~p",
               [z_context:site(Context), z_acl:user(Context), Kind, Id]),
    %% Assertion, can only delete edit version of a rule
    {ok, Row} = z_db:select(table(Kind), Id, Context),
    true = proplists:get_value(is_edit, Row),
    {ok, _} = z_db:delete(table(Kind), Id, Context),
    mod_acl_user_groups:rebuild(edit, Context),
    ok.

%% Remove all edit versions, add edit versions of published rules
revert(Kind, Context) ->
    lager:warning("[~p] ACL user groups revert by ~p of ~p",
                  [z_context:site(Context), z_acl:user(Context), Kind]),
    T = z_convert:to_list(table(Kind)),
    Result = z_db:transaction(
               fun(Ctx) ->
                       z_db:q("DELETE FROM " ++ T ++ " WHERE is_edit = true", Ctx),
                       All = z_db:assoc("SELECT * FROM " ++ T ++ " WHERE is_edit = false", Ctx),
                       [z_db:insert(table(Kind),
                                    z_utils:prop_delete(id, z_utils:prop_replace(is_edit, true, Row)),
                                    Context) || Row <- All],
                       ok
               end,
               Context),
    mod_acl_user_groups:rebuild(edit, Context),
    Result.


%% Remove all publish versions, add published versions of unpublished rules
publish(Kind, Context) ->
    lager:warning("[~p] ACL user groups publish by ~p",
                  [z_context:site(Context), z_acl:user(Context)]),
    T = z_convert:to_list(table(Kind)),
    Result = z_db:transaction(
               fun(Ctx) ->
                       z_db:q("DELETE FROM " ++ T ++ " WHERE is_edit = false", Ctx),
                       All = z_db:assoc("SELECT * FROM " ++ T ++ " WHERE is_edit = true", Ctx),
                       [z_db:insert(table(Kind),
                                    z_utils:prop_delete(id, z_utils:prop_replace(is_edit, false, Row)),
                                    Context) || Row <- All],
                       ok
               end,
               Context),
    mod_acl_user_groups:rebuild(publish, Context),
    Result.


manage_schema(_Version, Context) ->
    ensure_acl_rule_rsc(Context),
    ensure_acl_rule_module(Context).

ensure_acl_rule_rsc(Context) ->
    case z_db:table_exists(acl_rule_rsc, Context) of
        false ->
            z_db:create_table(acl_rule_rsc,
                              shared_table_columns() ++
                                  [
                                   #column_def{name=is_owner, type="boolean", is_nullable=false, default="false"},
                                   #column_def{name=category_id, type="integer", is_nullable=true},
                                   #column_def{name=content_group_id, type="integer", is_nullable=true}
                                  ],
                              Context),
            fk("acl_rule_rsc", "creator_id", Context),
            fk("acl_rule_rsc", "modifier_id", Context),
            fk("acl_rule_rsc", "acl_user_group_id", Context),
            fk("acl_rule_rsc", "content_group_id", Context),
            fk("acl_rule_rsc", "category_id", Context),
            ok;

        true ->
            ensure_column_is_block(acl_rule_rsc, Context),
            ok
    end.

ensure_acl_rule_module(Context) ->
    case z_db:table_exists(acl_rule_module, Context) of
        false ->
            z_db:create_table(acl_rule_module,
                              shared_table_columns() ++
                                  [
                                   #column_def{name=module, type="character varying", length=300, is_nullable=false}
                                  ],
                              Context),
            fk("acl_rule_module", "creator_id", Context),
            fk("acl_rule_module", "modifier_id", Context),
            fk("acl_rule_module", "acl_user_group_id", Context),
            ok;
        true ->
            ensure_column_is_block(acl_rule_module, Context),
            ok
    end,
    ok.

ensure_column_is_block(Table, Context) ->
    Columns = z_db:column_names(Table, Context),
    case lists:member(is_block, Columns) of
        true ->
            ok;
        false ->
            [] = z_db:q("alter table "++atom_to_list(Table)++" add column is_block boolean not null default false", Context),
            z_db:flush(Context)
    end.

shared_table_columns() ->
    [
     #column_def{name=id, type="serial", is_nullable=false},
     #column_def{name=is_edit, type="boolean", is_nullable=false, default="false"},
     #column_def{name=creator_id, type="integer", is_nullable=false},
     #column_def{name=modifier_id, type="integer", is_nullable=false},
     #column_def{name=created, type="timestamp", is_nullable=true},
     #column_def{name=modified, type="timestamp", is_nullable=true},
     #column_def{name=acl_user_group_id, type="integer", is_nullable=false},
     #column_def{name=is_block, type="boolean", is_nullable=false, default="false"},
     #column_def{name=actions, type="character varying", length=300, is_nullable=true}
    ].    

fk(Table, Field, Context) ->
    z_db:equery("alter table " ++ Table ++ " add constraint fk_" ++ Table ++ "_" ++ Field ++ "_id foreign key (" ++ Field ++ ") references rsc(id) on update cascade on delete cascade", Context).


import_rules(TmpFile, Context) ->
    {ok, Content} = file:read_file(TmpFile),
    RuleTypes = binary_to_term(Content),
    z_db:transaction(
      fun(Ctx) ->
              [begin
                   {Kind, State, Rules0} = Row,
                   Rules = names_to_ids(Rules0, Context),
                   Query = "DELETE FROM " ++ z_convert:to_list(table(Kind)) 
                       ++ " WHERE " ++ state_sql_clause(State),
                   z_db:equery(Query, Ctx),
                   Rules1 = controller_admin_acl_rules_export:names_to_ids(Rules, Context),
                   [z_db:insert(table(Kind), R, Ctx) || R <- Rules1]
               end
               || Row <- RuleTypes]
      end,
      Context),
    mod_acl_user_groups:rebuild(edit, Context),
    mod_acl_user_groups:rebuild(publish, Context),
    ok.


ids_to_names(Rows, Context) ->
    [ids_to_names_row(R, Context) || R <- Rows].

ids_to_names_row(R, Context) ->
    lists:foldl(
      fun(K, Acc) ->
              Value = proplists:get_value(K, Acc),
              case is_integer(Value) of
                  true ->
                      %% look up name
                      case m_rsc:p(Value, name, Context) of
                          undefined ->
                              %% nope, keep id
                              Acc;
                          Name ->
                              z_utils:prop_replace(K, Name, Acc)
                      end;
                  false ->
                      Acc
              end
      end,
      R,
      fields()).

names_to_ids(Rows, Context) ->
    [names_to_ids_row(R, Context) || R <- Rows].

names_to_ids_row(R, Context) ->
    lists:foldl(
      fun(actions, Acc) ->
              A1 = implode_actions(proplists:get_value(actions, Acc)),
              z_utils:prop_replace(actions, A1, Acc);
         (K, Acc) ->
              Value = proplists:get_value(K, Acc),
              case is_binary(Value) of
                  true ->
                      %% look up name
                      case m_rsc:name_to_id(Value, Context) of
                          {ok, Id} ->
                              z_utils:prop_replace(K, Id, Acc);
                          _ ->
                              Acc
                      end;
                  false ->
                      Acc
              end
      end,
      R,
      [actions|fields()]).

fields() ->
    [acl_user_group_id, category_id, content_group_id, creator_id, modifier_id].

implode_actions(L) ->
    string:join(
      [z_convert:to_list(K) || {K, true} <- L],
      ",").
