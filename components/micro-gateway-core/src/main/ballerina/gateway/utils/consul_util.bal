// Copyright (c)  WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/log;
import ballerina/auth;
import ballerina/config;
import ballerina/runtime;
import ballerina/time;
import ballerina/io;
import ballerina/reflect;
import ballerina/internal;
import ballerina/system;

public map consulUrls;
public map consulUrlChanged;
map consulDefaultUrls;
string consulToken;
boolean consulPeriodicQueryInitialized = false;
public boolean consulConnectionEstablished = true;
boolean consulConnectionAttempted = false;
boolean consulcredentialsProvided = false;
boolean consulAuthenticationEnabled = true;
task:Timer? consulTimer;
string consulKVBasePath = "/v1/kv/";

@Description {value:"Setting up consul timer task"}
public function initiateConsulTimerTask() {
    printDebug(KEY_CONSUL_UTIL, "initiateConsulTimerTask Called");
    int consulTriggerTime = config:getAsInt("consultimer", default = DEFAULT_SERVICE_DISCOVERY_TRIGGER_TIME);
    (function() returns error?) onTriggerFunction = consulTimerTask;
    function(error) onErrorFunction = consulError;
    consulTimer = new task:Timer(onTriggerFunction, onErrorFunction, consulTriggerTime, delay = 1000);
    consulTimer.start();
    printInfo(KEY_CONSUL_UTIL, "Consul periodic timer task started with a periodic time of " + <string>consulTriggerTime + "ms");
}

@Description {value:"Periodic consul Query. Trigger function of consul timer task"}
public function consulTimerTask() returns error? {
    printDebug(KEY_CONSUL_UTIL, "Consul Periodic Query Initiated");
    if (consulUrls.count() > 0) {
        foreach key, value in consulUrls {

            string currentUrl = <string>value;
            string fetchedUrl = consulLookup(<string>key);

            if (currentUrl != fetchedUrl) {
                consulUrls[<string>key] = fetchedUrl;
                consulUrlChanged[<string>key] = true;
            }
        }
    } else {
        printInfo(KEY_CONSUL_UTIL, "No Consul keys provided. Stopping consul periodic call");
        consulTimer.stop();
    }

    return ();
}

@Description {value:"Error function of consul timer task"}
public function consulError(error e) {
    printError(KEY_CONSUL_UTIL, "Consul Timer Task failed");
}

@Description {value:"Setting up consul requirements"}
public function consulSetup(string key, string consulConfigKey, string default) returns string {
    string endpointUrl;

    if (!consulConnectionAttempted) {
        establishConsulConnection();
        consulConnectionAttempted = true;
        printDebug(KEY_CONSUL_UTIL, "Consul Connection Attempted");
    }

    if (consulConnectionEstablished) {
        if (!consulPeriodicQueryInitialized) {
            consulPeriodicQueryInitialized = true;
            initiateConsulTimerTask();
        }
        string consulKey = retrieveConfig(consulConfigKey, "");

        if (consulKey == "") {
            printInfo(KEY_CONSUL_UTIL, "Consul Key not provided for: " + key);
            endpointUrl = retrieveConfig(key, default);
        } else {
            printDebug(KEY_CONSUL_UTIL, "Consul Key provided for: " + key);
            consulDefaultUrls[consulKey] = retrieveConfig(key, default);
            consulUrlChanged[consulKey] = false;
            consulUrls[consulKey] = consulLookup(consulKey);
            endpointUrl = <string>consulUrls[consulKey];
        }
    } else {
        endpointUrl = retrieveConfig(key, default);
    }
    return endpointUrl;
}

@Description {value:"Establish consul connection by authenticating consul"}
public function establishConsulConnection() {
    printDebug(KEY_CONSUL_UTIL, "Establishing Consul Connection");
    string consulurl = retrieveConfig("consulurl", "");
    if (consulurl != "") {
        printDebug(KEY_CONSUL_UTIL, "consulurl CLI parameter has been provided");
        string sample = consulLookup("sample");
    } else {
        printError(KEY_CONSUL_UTIL, "consulurl CLI parameter has not been provided");
        consulConnectionEstablished = false;
    }
}

@Description {value:"Query consul passing the key and retrieves value"}
public function consulLookup(string key) returns string {
    string endpointUrl;
    string base64EncodedValue;
    http:Request req;
    boolean valueNotFound = false;
    string apiRequestPath = consulKVBasePath + key;
    string token = retrieveConfig("token", "");

    if (token != "") {
        req.setHeader("X-Consul-Token", token);
        printDebug(KEY_CONSUL_UTIL, "Adding consul token to request header");
    }

    var response = consulEndpoint->get(apiRequestPath, message = req);
    match response {
        http:Response resp => {
            printDebug(KEY_CONSUL_UTIL, "Http Response object obtained");
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    printDebug(KEY_CONSUL_UTIL, "consul responded with a payload");
                    var payloadValue = <string>jsonPayload[0].Value;
                    match payloadValue {
                        string matchedValue => base64EncodedValue = matchedValue;
                        error err => valueNotFound = true;
                    }
                }
                error err => {
                    valueNotFound = true;
                    if (resp.statusCode == 403) {
                        printError(KEY_CONSUL_UTIL, "Permission denied. Invalid token");
                        consulConnectionEstablished = false;
                    } else if (resp.statusCode == 404) {
                        printDebug(KEY_CONSUL_UTIL, "Value for key " + key + "not found at Consul node.");
                    } else {
                        printError(KEY_CONSUL_UTIL, err.message);
                    }
                }
            }
        }
        error err => {
            printDebug(KEY_CONSUL_UTIL, "Error object obtained");
            consulConnectionEstablished = false;
            valueNotFound = true;
            printError(KEY_CONSUL_UTIL, err.message);
        }
    }
    if (valueNotFound) {
        printInfo(KEY_CONSUL_UTIL, "value not found at consul");
        endpointUrl = <string>consulDefaultUrls[key];
    } else {
        printInfo(KEY_CONSUL_UTIL, "value found at consul");
        endpointUrl = decodeValueToBase10(base64EncodedValue);
    }
    return endpointUrl;
}

