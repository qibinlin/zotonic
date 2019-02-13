/**
 * Copyright 2019 Marc Worrell <marc@worrell.nl>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS-IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

"use strict";

// TODO:
// - recheck auth after ws connect and no recent auth check (or failed check)
//   this could be due to browser wakeup or server down time.

////////////////////////////////////////////////////////////////////////////////
// Model
//

var model = {
        status: 'start',
        is_status_changed: false,
        is_keep_alive: false,
        authentication_error: null,
        auth: {
            status: 'pending',
            is_authenticated: false,
            user_id: null,
            username: null,
            preferences: {
            }
        }
    };

model.present = function(data) {
    let previous_auth_user_id = model.auth.user_id;

    if (state.start(model)) {
        // Handle auth changes forced by changes of the session storage
        self.subscribe("model/sessionStorage/event/auth-user-id", function(msg) {
            actions.setUserId({ user_id: msg.payload });
        });

        // Synchronize tabs and windows of same user-agent
        self.subscribe("model/serviceWorker/event/auth-sync", function(msg) {
            actions.sync(msg.payload);
        });

        // Auth requests from the JS applications
        self.subscribe("model/auth/post/logon", function(msg) {
            actions.logon(msg.payload);
        });
        self.subscribe("model/auth/post/logoff", function(msg) {
            actions.logoff(msg.payload);
        });

        self.subscribe("model/auth/post/logon/form", function(msg) {
            actions.logonForm(msg.payload);
        });

        // Keep-alive ping for token refresh
        self.subscribe("model/ui/event/recent-activity", function(msg) {
            if (msg.payload.is_active) {
                actions.keepAlive(msg.payload);
            }
        });
    }

    if (state.start(model) || ("user_id" in data && data.user_id !== model.auth.user_id)) {
        model.state_change('auth_unknown');

        // Refresh the current auth status by probing the server
        fetch( self.abs_url("/zotonic-auth"), {
            method: "POST",
            cache: "no-cache",
            headers: {
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ cmd: "status" })
        })
        .then(function(resp) { return resp.json(); })
        .then(function(body) { actions.authResponse(body); })
        .catch((e) => { actions.authError(); });
    }

    if (data.is_auth_check && (state.authKnown(model) || state.authError(model))) {
        let auth_check_cmd = 'status';
        if (model.is_keep_alive && model.auth.is_authenticated) {
            auth_check_cmd = 'refresh';
        }
        model.is_keep_alive = false;
        fetch( self.abs_url("/zotonic-auth"), {
            method: "POST",
            cache: "no-cache",
            headers: {
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ cmd: auth_check_cmd })
        })
        .then(function(resp) { return resp.json(); })
        .then(function(body) { actions.authResponse(body); })
        .catch((e) => { actions.authError(); });
    }

    if (data.logon) {
        model.authentication_error = null;
        model.onauth = data.onauth || null;
        model.state_change('authenticating');

        fetch( self.abs_url("/zotonic-auth"), {
            method: "POST",
            cache: "no-cache",
            headers: {
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                    cmd: "logon",
                    username: data.username,
                    password: data.password,
                    passcode: data.passcode
                })
        })
        .then(function(resp) { return resp.json(); })
        .then(function(body) { actions.authLogonResponse(body); })
        .catch((e) => { actions.authError(); });
    }

    if (data.logoff) {
        model.authentication_error = null;
        model.onauth = data.onauth || null;
        model.state_change('authenticating');

        fetch( self.abs_url("/zotonic-auth"), {
            method: "POST",
            cache: "no-cache",
            headers: {
                "Accept": "application/json",
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ cmd: "logoff" })
        })
        .then(function(resp) { return resp.json(); })
        .then(function(body) { actions.authResponse(body); })
        .catch((e) => { actions.authError(); });
    }

    if ("auth_response" in data && data.auth_response.status == 'ok') {
        model.auth = data.auth_response;
        if (model.auth.user_id == previous_auth_user_id) {
            model.state_change('auth_known');
        } else {
            model.state_change('auth_changing');
        }
    }

    if (data.is_auth_error && state.authenticating(model)) {
        model.authentication_error = data.error;
        model.state_change('auth_error');
    }

    if (data.is_auth_changed && state.authChanging(model)) {
        model.state_change('auth_known');
    }

    if (data.is_keep_alive) {
        model.is_keep_alive = true;
    }

    // console.log("AUTH state", model);
    state.render(model) ;
}

model.state_change = function(status) {
    if (status != model.status) {
        switch (status) {
            case 'auth_changing':
                self.publish('model/auth/event/auth-changing', {
                    onauth: model.onauth,
                    auth: model.auth
                });
                setTimeout(function() { actions.authChanged(); }, 20);
                break;
            case 'auth_known':
                self.publish('model/auth/event/auth-user-id', model.auth.user_id);
                self.publish('model/sessionStorage/post/auth-user-id', model.auth.user_id);
                self.publish('model/serviceWorker/post/broadcast/auth-sync', model.auth);
                break;
            default:
                break;
        }
        model.status = status;
    }
}

////////////////////////////////////////////////////////////////////////////////
// View
//
var view = {} ;

// Initial State
view.init = function(model) {
    return view.ready(model) ;
}

// State representation of the ready state
view.ready = function(model) {
    return "";
}


//display the state representation
view.display = function(representation) {
}

// Display initial state
view.display(view.init(model)) ;


////////////////////////////////////////////////////////////////////////////////
// State
//
var state =  { view: view} ;

model.state = state ;

// Derive the state representation as a function of the systen control state
state.representation = function(model) {
    self.publish('model/auth/event/auth', model.auth);

    // var representation = 'oops... something went wrong, the system is in an invalid state' ;
    // if (state.ready(model)) {
    //     representation = state.view.ready(model) ;
    // }
    // ...
    // state.view.display(representation) ;
}

// Derive the current state of the system
state.start = function(model) {
    return model.status === 'start';
}

state.authKnown = function(model) {
    return model.status === 'auth_known' || model.auth.status == 'ok';
}

state.authUnknown = function(model) {
    return !state.authKnown(model);
}

state.authChanging = function(model) {
    return model.status === 'auth_changing';
}

state.authenticating = function(model) {
    return model.status === 'authenticating';
}

state.authError = function(model) {
    return model.status === 'auth_error';
}

// Next action predicate, derives whether
// the system is in a (control) state where
// an action needs to be invoked

state.nextAction = function (model) {
}

state.render = function(model) {
    state.representation(model)
    state.nextAction(model) ;
}


////////////////////////////////////////////////////////////////////////////////
// Actions
//

var actions = {} ;

// On startup we continue with the previous page user-id
// todo: check the returned html for any included user-id (from the cookie
//       when generating the page, should be data attribute in html tag).
actions.start = function() {
    self.call("model/sessionStorage/get/auth-user-id")
        .then((msg) => {
            model.auth.user_id = msg.payload;
            model.present({});
        });
}

actions.setUserId = function(data) {
    data = data || {};
    if ("user_id" in data) {
        model.present(data);
    }
}

actions.authResponse = function(data) {
    data = data || {};
    model.present({ auth_response: data });
}

actions.authLogonResponse = function(data) {
    switch (data.status) {
        case "ok":
            model.present({ auth_response: data });
            break;
        case "error":
            model.present({
                    is_auth_error: true,
                    error: data.error
                });
            break;
    }
}

actions.authError = function(_data) {
    model.present({ is_auth_error: true });
}

actions.authChanged = function(_data) {
    model.present({ is_auth_changed: true });
}

actions.authCheck = function(_data) {
    model.present({ is_auth_check: true });
}

actions.logon = function(data) {
    let dataLogon = {
        logon: true,
        username: data.username,
        password: data.password,
        passcode: data.passcode
    };
    model.present(dataLogon)
}

actions.logonForm = function(data) {
    let dataLogon = {
        logon: true,
        username: data.value.username,
        password: data.value.password,
        passcode: data.value.passcode,
        onauth: data.value.onauth
    }
    model.present(dataLogon);
}

actions.logoff = function(data) {
    model.present({ logoff: true });
}

actions.keepAlive = function(_date) {
    model.present({ is_keep_alive: true });
}

////////////////////////////////////////////////////////////////////////////////
// Worker Startup
//

self.on_connect = function() {
    setTimeout(function() { actions.start(); }, 0);
    setInterval(function() { actions.authCheck(); }, 30000);
}

self.connect();
