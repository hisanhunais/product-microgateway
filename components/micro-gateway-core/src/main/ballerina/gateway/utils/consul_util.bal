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
public map consulurlChanged;
map consuldefaultUrls;
string consulToken;
boolean consulPeriodicQueryInitialized = false;
public boolean consulConnectionEstablished = true;
boolean consulConnectionAttempted = false;
boolean consulcredentialsProvided = false;
boolean consulAuthenticationEnabled = true;
task:Timer? consulTimer;
string consulKVBasePath = "/v1/kv/";
string consulAuthBasePath = "/v1/auth";

@Description {value:"Setting up etcd timer task"}
public function initiateConsulTimerTask()
{
    printDebug(KEY_CONSUL_UTIL, "initiateConsulTimerTask Called");
    int consulTriggerTime = config:getAsInt("consultimer", default = DEFAULT_ETCD_TRIGGER_TIME);
    (function() returns error?) onTriggerFunction = consulTimerTask;
    function(error) onErrorFunction = consulError;
    consulTimer = new task:Timer(onTriggerFunction, onErrorFunction, consulTriggerTime, delay = 1000);
    consulTimer.start();
    printInfo(KEY_CONSUL_UTIL, "Consul periodic timer task started with a periodic time of " + <string>consulTriggerTime + "ms");
}

@Description {value:"Periodic Etcd Query. Trigger function of etcd timer task"}
public function consulTimerTask() returns error? {io:println("here3");
    printDebug(KEY_CONSUL_UTIL, "Etcd Periodic Query Initiated");
    if(consulUrls.count() > 0)
    {
        foreach k, v in consulUrls {

            string currentUrl = <string>v;
            string fetchedUrl = consulLookup(<string>k);

            if(currentUrl != fetchedUrl)
            {
                consulUrls[<string>k] = fetchedUrl;
                consulurlChanged[<string>k] = true;
            }
        }
        io:println(consulUrls);
    }
    else
    {
        printInfo(KEY_CONSUL_UTIL, "No Consul keys provided. Stopping consul periodic call");
        consulTimer.stop();
    }

    return ();
}

@Description {value:"Error function of etcd timer task"}
public function consulError(error e) {
    printError(KEY_CONSUL_UTIL, "Consul Timer Task failed");
}

@Description {value:"Setting up etcd requirements"}
public function consulSetup(string key, string etcdConfigKey, string default) returns string
{
    string endpointUrl;

    if(!consulConnectionAttempted)
    {
        establishConsulConnection();
        consulConnectionAttempted = true;
        printDebug(KEY_CONSUL_UTIL, "Etcd Connection Attempted");
    }

    if(consulConnectionEstablished)
    {
        if(!consulPeriodicQueryInitialized)
        {
            consulPeriodicQueryInitialized = true;
            initiateConsulTimerTask();
        }
        string etcdKey = retrieveConfig(etcdConfigKey, "");

        if(etcdKey == "")
        {
            printInfo(KEY_CONSUL_UTIL, "Consul Key not provided for: " + key);
            endpointUrl = retrieveConfig(key, default);
        }
        else
        {
            printDebug(KEY_CONSUL_UTIL, "Consul Key provided for: " + key);
            consuldefaultUrls[etcdKey] = retrieveConfig(key, default);
            consulurlChanged[etcdKey] = false;
            consulUrls[etcdKey] = consulLookup(etcdKey);
            endpointUrl = <string>consulUrls[etcdKey];
        }
    }
    else
    {   io:println("here5");
        endpointUrl = retrieveConfig(key, default);
    }
    io:println(endpointUrl);
    return endpointUrl;
}

@Description {value:"Establish etcd connection by authenticating etcd"}
public function establishConsulConnection()
{
    printDebug(KEY_CONSUL_UTIL, "Establishing Consul Connection");
    string consulurl = retrieveConfig("consulurl", "");
    if(consulurl != ""){
        printDebug(KEY_CONSUL_UTIL, "etcdurl CLI parameter has been provided");
        string sample = consulLookup("sample");
    } else {
        printError(KEY_CONSUL_UTIL, "Etcd URL not provided");
        consulConnectionEstablished = false;
    }
}

@Description {value:"Query etcd passing the key and retrieves value"}
public function consulLookup(string key) returns string
{
    string endpointUrl;
    string base64EncodedValue;
    http:Request req;
    boolean valueNotFound = false;
    string requestPath = consulKVBasePath + key;
    string token = retrieveConfig("token", "");

    if(token != "")
    {
        req.setHeader("X-Consul-Token", token);
        printDebug(KEY_CONSUL_UTIL, "Adding consul token to request header");
    }

    var response = consulEndpoint->get(requestPath, message = req);
    match response {
        http:Response resp => {
            printDebug(KEY_CONSUL_UTIL, "Http Response object obtained");
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    printDebug(KEY_CONSUL_UTIL, "etcd responded with a payload");
                    var payloadValue = <string>jsonPayload[0].Value;
                    match payloadValue {
                        string matchedValue => base64EncodedValue = matchedValue;
                        error err => valueNotFound = true;
                    }
                }
                error err => {
                    valueNotFound = true;
                    if(resp.statusCode == 403){
                        printError(KEY_CONSUL_UTIL, "Permission denied. Invalid token");
                        consulConnectionEstablished = false;
                    }else if (resp.statusCode == 404){
                        printDebug(KEY_CONSUL_UTIL, "Value for key " + key + "not found at Consul node.");
                    }
                    else{
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

    if(valueNotFound){
        printDebug(KEY_CONSUL_UTIL, "value not found at etcd");
        endpointUrl = <string>defaultUrls[key];
    } else {
        printDebug(KEY_CONSUL_UTIL, "value found at etcd");
        endpointUrl = decodeValueToBase10(base64EncodedValue);
    }
    return endpointUrl;
}

@Description {value:"Authenticate etcd by providing username and password and retrieve etcd token"}
public function consulAuthenticate()
{
    printDebug(KEY_ETCD_UTIL, "Authenticating Etcd");
    http:Request req;

    consulToken = retrieveConfig("token", "");

    if(consulToken == ""){
        printDebug(KEY_ETCD_UTIL, "consul token has not been provided");
        req.setHeader("X-Consul-Token", consulToken);
        credentialsProvided = false;
    } else {
        printDebug(KEY_ETCD_UTIL, "consul token has been provided");
        credentialsProvided = true;
    }


    req.setPayload("sample_value");

    var response = consulEndpoint->put("/v1/kv/sample", req);
    match response {
        http:Response resp => {io:println(resp);
            printDebug(KEY_ETCD_UTIL, "Http Response object obtained");
            var msg = resp.getJsonPayload();io:println(msg);
            match msg {
                json jsonPayload => {
                    //if(jsonPayload.token!= null)
                    //{
                    //    printDebug(KEY_ETCD_UTIL, "etcd has responded with a token");
                    //    etcdConnectionEstablished = true;
                    //    var token = <string>jsonPayload.token;
                    //    match token {
                    //        string value => {
                    //            etcdToken = untaint value;
                    //            etcdConnectionEstablished = true;
                    //            printInfo(KEY_ETCD_UTIL, "Etcd Authentication Successful");
                    //        }
                    //        error err => {
                    //            etcdConnectionEstablished = false;
                    //            printError(KEY_ETCD_UTIL, err.message);
                    //        }
                    //    }
                    //}
                    if(jsonPayload.error!=null)
                    {
                        printDebug(KEY_ETCD_UTIL, "etcd has responded with an error");
                        var authenticationError = <string>jsonPayload.error;
                        match authenticationError {
                            string value => {
                                if(value.contains("authentication is not enabled"))
                                {
                                    printDebug(KEY_ETCD_UTIL, "etcd authentication is not enabled");
                                    etcdAuthenticationEnabled = false;
                                    etcdConnectionEstablished = true;
                                    if(credentialsProvided)
                                    {
                                        printInfo(KEY_ETCD_UTIL, value);
                                    }
                                }
                                if(value.contains("authentication failed, invalid user ID or password"))
                                {
                                    etcdConnectionEstablished = false;
                                    printError(KEY_ETCD_UTIL, value);
                                }
                            }
                            error err => {
                                etcdConnectionEstablished = false;
                                printError(KEY_ETCD_UTIL, err.message);
                            }
                        }
                    }
                    else{
                        printDebug(KEY_ETCD_UTIL, "etcd has responded with a token");
                        etcdConnectionEstablished = true;
                    }
                }
                error err => {
                    etcdConnectionEstablished = false;
                    printError(KEY_ETCD_UTIL, err.message);
                }
            }
        }
        error err => {
            printDebug(KEY_ETCD_UTIL, "Error object obtained");
            etcdConnectionEstablished = false;
            printError(KEY_ETCD_UTIL, err.message);
        }
    }
}