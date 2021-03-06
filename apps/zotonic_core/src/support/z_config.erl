%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2010-2017 Marc Worrell, 2014 Arjan Scherpenisse
%% @doc Wrapper for Zotonic application environment configuration

%% Copyright 2010-2017 Marc Worrell, 2014 Arjan Scherpenisse
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

-module(z_config).
-author("Marc Worrell <marc@worrell.nl>").

%% API export
-export([
    get/1,
    get/2,

    init_app_env/0,
    maybe_map_env/1
]).


-include_lib("zotonic.hrl").

%%====================================================================
%% API
%%====================================================================

%% @doc Copy some zotonic config settings over to other applications
-spec init_app_env() -> ok.
init_app_env() ->
    application:set_env(cowmachine, proxy_whitelist, ?MODULE:get(proxy_whitelist)),
    application:set_env(cowmachine, ip_whitelist, ?MODULE:get(ip_whitelist)),
    ok.


%% @doc Get value from config file (cached)
%%
%% Some config settings can be overruled by environment settings.
-spec get(atom()) -> any().
get(listen_ip) ->
    IPv4 = case os:getenv("ZOTONIC_IP") of
        false -> ?MODULE:get(listen_ip, default(listen_ip));
        IP -> IP
    end,
    maybe_map_value(listen_ip, IPv4);
get(listen_ip6) ->
    IPv6 = case os:getenv("ZOTONIC_IP6") of
        false -> get(listen_ip6, default(listen_ip6));
        IP -> IP
    end,
    maybe_map_value(listen_ip6, IPv6);
get(listen_port) ->
    case os:getenv("ZOTONIC_LISTEN_PORT") of
        false -> ?MODULE:get(listen_port, default(listen_port));
        "" -> ?MODULE:get(listen_port, default(listen_port));
        "none" -> none;
        Port -> list_to_integer(Port)
    end;
get(port) ->
    case os:getenv("ZOTONIC_PORT") of
        false -> get(port, default(port));
        "" -> get(port, default(port));
        "none" -> none;
        Port -> list_to_integer(Port)
    end;
get(ssl_listen_port) ->
    case os:getenv("ZOTONIC_SSL_LISTEN_PORT") of
        false -> ?MODULE:get(ssl_listen_port, default(ssl_listen_port));
        "" -> ?MODULE:get(ssl_listen_port, default(ssl_listen_port));
        "none" -> none;
        Port -> list_to_integer(Port)
    end;
get(ssl_port) ->
    case os:getenv("ZOTONIC_SSL_PORT") of
        false -> get(ssl_port, default(ssl_port));
        "" -> get(ssl_port, default(ssl_port));
        "none" -> none;
        Port -> list_to_integer(Port)
    end;
get(smtp_listen_domain) ->
    case os:getenv("ZOTONIC_SMTP_LISTEN_DOMAIN") of
        false -> get(smtp_listen_domain, default(smtp_listen_domain));
        SmtpListenDomain_ -> SmtpListenDomain_
    end;
get(smtp_listen_ip) ->
    SmtpIp = case os:getenv("ZOTONIC_SMTP_LISTEN_IP") of
        false -> ?MODULE:get(smtp_listen_ip, default(smtp_listen_ip));
        "none" -> none;
        SmtpListenIp -> SmtpListenIp
    end,
    maybe_map_value(smtp_listen_ip, SmtpIp);
get(smtp_listen_port) ->
    case os:getenv("ZOTONIC_SMTP_LISTEN_PORT") of
        false -> ?MODULE:get(smtp_listen_port, default(smtp_listen_port));
        "none" -> none;
        SmtpListenPort_ -> list_to_integer(SmtpListenPort_)
    end;
get(smtp_spamd_ip) ->
    maybe_map_value(smtp_spamd_ip, ?MODULE:get(smtp_spamd_ip, default(smtp_spamd_ip)));
get(Key) ->
    ?MODULE:get(Key, default(Key)).

%% @doc Get value from config file, returning default value when not set (cached).
-spec get(atom(), any()) -> any().
get(Key, Default) ->
	case application:get_env(zotonic_core, Key) of
		undefined ->
			maybe_map_value(Key, maybe_map_env(Default));
		{ok, Value} ->
			maybe_map_value(Key, maybe_map_env(Value))
	end.

maybe_map_env({env, Name}) -> os:getenv(Name);
maybe_map_env({env, Name, Default}) -> os:getenv(Name, Default);
maybe_map_env({env_int, Name}) -> z_convert:to_integer(os:getenv(Name));
maybe_map_env({env_int, Name, Default}) -> z_convert:to_integer(os:getenv(Name, Default));
maybe_map_env(V) -> V.

%% @doc Translate IP addresses to a tuple(), 'any', or 'none'
-spec maybe_map_value(atom(), term()) -> term().
maybe_map_value(listen_ip, IP) -> map_ip_address(listen_ip, IP);
maybe_map_value(listen_ip6, IP) -> map_ip_address(listen_ip6, IP);
maybe_map_value(smtp_listen_ip, IP) -> map_ip_address(smtp_listen_ip, IP);
maybe_map_value(smtp_spamd_ip, IP) -> map_ip_address(smtp_spamd_ip, IP);
maybe_map_value(_Key, Value) ->
    Value.

map_ip_address(_Name, any) -> any;
map_ip_address(_Name, "any") -> any;
map_ip_address(_Name, "") -> any;
map_ip_address(_Name, "*") -> any;
map_ip_address(_Name, none) -> none;
map_ip_address(_Name, "none") -> none;
map_ip_address(_Name, IP) when is_tuple(IP) -> IP;
map_ip_address(Name, IP) when is_list(IP) ->
    case getaddr(Name, IP) of
        {ok, IpN} -> IpN;
        {error, Reason} ->
            lager:error("Invalid '~p' address: ~p, assuming 'none' instead (~p)",
                        [Name, IP, Reason]),
            none
    end;
map_ip_address(smtp_spamd_ip, undefined) ->
    none;
map_ip_address(Name, IP) ->
    lager:error("Invalid ~p address: ~p, assuming 'any' instead",
                [Name, IP]),
    any.

getaddr(listen_ip6, IP) -> inet:getaddr(IP, inet6);
getaddr(_Name, IP) -> inet:getaddr(IP, inet).

default(timezone) -> <<"UTC">>;
default(listen_ip) -> any;
default(listen_ip6) ->
    % Default to the listen_ip configuration iff that configuration
    % is not a IPv4 address
    ListenIP4 = case os:getenv("ZOTONIC_IP") of
        false -> ?MODULE:get(listen_ip, default(listen_ip));
        IP -> IP
    end,
    case ListenIP4 of
        any -> any;
        "any" -> any;
        "" -> any;
        "*" -> any;
        none -> none;
        "none" -> none;
        {127,0,0,1} -> "::1";
        {_,_,_,_} -> none;
        Domain when is_list(Domain) ->
            % Only use the domain if it is not a dotted ip4 number
            case re:run(Domain, "^[0-9]{1,3}(\\.[0-9]{1,3}){3}$") of
                {match, _} -> none;
                _ -> Domain
            end
    end;
default(listen_port) -> 8000;
default(ssl_listen_port) -> 8443;
default(port) -> ?MODULE:get(listen_port);
default(ssl_port) -> ?MODULE:get(ssl_listen_port);
default(ssl_only) -> false;
default(smtp_verp_as_from) -> false;
default(smtp_no_mx_lookups) -> false;
default(smtp_relay) -> false;
default(smtp_host) -> "localhost";
default(smtp_port) -> 25;
default(smtp_ssl) -> false;
default(smtp_listen_ip) -> {127,0,0,1};
default(smtp_listen_port) -> 2525;
default(smtp_spamd_ip) -> none;
default(smtp_spamd_port) -> 783;
default(smtp_dnsbl) -> z_email_dnsbl:dnsbl_list();
default(smtp_dnswl) -> z_email_dnsbl:dnswl_list();
default(smtp_delete_sent_after) -> 240;
default(inet_backlog) -> 500;
default(inet_acceptor_pool_size) -> 100;
default(ssl_backlog) -> ?MODULE:get(inet_backlog);
default(ssl_acceptor_pool_size) -> ?MODULE:get(inet_acceptor_pool_size);
default(ssl_dhfile) -> undefined;
default(dbhost) -> "localhost";
default(dbport) -> 5432;
default(dbuser) -> "zotonic";
default(dbpassword) -> "";
default(dbdatabase) -> "zotonic";
default(dbschema) -> "public";
default(filewatcher_enabled) -> true;
default(filewatcher_scanner_enabled) -> false;
default(syslog_ident) -> "zotonic";
default(syslog_opts) -> [ndelay];
default(syslog_facility) -> local0;
default(syslog_level) -> info;
default(user_sites_dir) -> "_checkouts";
default(user_modules_dir) -> "_checkouts";
default(proxy_whitelist) -> local;
default(ip_whitelist) -> local;
default(sessionjobs_limit) -> erlang:max(erlang:system_info(process_limit) div 10, 10000);
default(sidejobs_limit) -> erlang:max(erlang:system_info(process_limit) div 2, 50000);
default(server_header) -> "Zotonic";
default(html_error_path) -> filename:join(code:priv_dir(zotonic_core), "htmlerrors");
default(_) -> undefined.
