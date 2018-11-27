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
public map consuldefaultUrls;
public boolean consulPeriodicQueryInitialized = false;
public boolean consulConnectionEstablished = false;
public boolean consulConnectionAttempted = false;
public string consulToken;
public boolean consulUrlValid = false;
task:Timer? consulTimer;

@Description {value:"Setting up consul timer task"}
public function initiateConsulPeriodicQuery()
{
    int consulTriggerTime = config:getAsInt("consultimer", default = DEFAULT_CONSUL_TRIGGER_TIME);
    (function() returns error?) onTriggerFunction = consulPeriodicQuery;
    function(error) onErrorFunction = consulError;
    consulTimer = new task:Timer(onTriggerFunction, onErrorFunction, consulTriggerTime, delay = 1000);
    consulTimer.start();
    printInfo(KEY_CONSUL_UTIL, "Consul Periodic Timer Task Started");
}

@Description {value:"Periodic Consul Query. Trigger function of consul timer task"}
public function consulPeriodicQuery() returns error? {
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

@Description {value:"Error function of consul timer task"}
public function consulError(error e) {
    printError(KEY_CONSUL_UTIL, "Consul Timer Task failed");
}

@Description {value:"Setting up consul requirements"}
public function consulSetup(string key, string default, string configKey) returns string
{
    string endpointUrl;

    if (!consulPeriodicQueryInitialized)
    {
        consulPeriodicQueryInitialized = true;
        initiateConsulPeriodicQuery();
    }
    string consulKey = retrieveConfig(configKey, "");

    if (consulKey == "")
    {
        printInfo(KEY_CONSUL_UTIL, "Consul Key not provided for: " + key);
        endpointUrl = retrieveConfig(key, default);
    }
    else
    {
        consuldefaultUrls[consulKey] = default;
        consulurlChanged[consulKey] = false;
        consulUrls[consulKey] = consulLookup(consulKey);
        endpointUrl = <string>consulUrls[consulKey];
    }

    return endpointUrl;
}

@Description {value:"Establish consul connection by authenticating consul"}
public function establishConsulConnection()
{
    string consulurl = retrieveConfig("consulurl", "");
    boolean authenticated;
    if(consulurl != "")
    {
        authenticated = consulAuthenticate();
        if(consulUrlValid)
        {
            if(authenticated)
            {
                printInfo(KEY_CONSUL_UTIL, "Consul Authentication Successful");
                consulConnectionEstablished = true;
            }
            else
            {
                printInfo(KEY_CONSUL_UTIL, "Consul Authentication Failed");
                consulConnectionEstablished = false;
            }
        }
        else
        {
            printInfo(KEY_CONSUL_UTIL, "Invalid Consul Url Provided");
            consulConnectionEstablished = false;
        }
    }
    else
    {
        printInfo(KEY_CONSUL_UTIL, "Consul URL not provided");
        consulConnectionEstablished = false;
    }
}

@Description {value:"Query consul passing the key and retrieves value"}
public function consulLookup(string key10) returns string
{
    string key64;
    string value64;
    string endpointUrl;
    http:Request req;

    //var key = key10.base64Encode(charset = "utf-8");
    //match key {
    //    string matchedKey => key64 = matchedKey;
    //    error err => log:printError(err.message, err = err);
    //}

    //req.setPayload({"key": untaint key64});
    //req.setHeader("Authorization", consulToken);
    string path = "/v1/kv/"+key10;
    var response = consulEndpoint->get(path);
    match response {
        http:Response resp => {
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    var val64 = <string>jsonPayload[0].Value;
                    match val64 {
                        string matchedValue => value64 = matchedValue;
                        error err => { value64 = "Not found"; }
                    }
                }
                error err => {
                    log:printError(err.message, err = err);
                }
            }
        }
        error err => {
            log:printError(err.message, err = err);
            value64 = "Not found";
        }
    }

    if(value64 == "Not found")
    {
        endpointUrl = <string>consuldefaultUrls[key10];
    }
    else
    {
        var value10 = value64.base64Decode(charset = "utf-8");
        match value10 {
            string matchedValue10 => endpointUrl = untaint matchedValue10;
            error err => log:printError(err.message, err = err);
        }
    }
    return endpointUrl;
}

@Description {value:"Authenticate consul by providing username and password and retrieve consul token"}
public function consulAuthenticate() returns boolean
{
    http:Request req;
    boolean consulAuthenticated = false;

    string username = retrieveConfig("consulusername", "");
    string password = retrieveConfig("consulpassword", "");

    req.setPayload({"name": untaint username, "password": untaint password});

    var response = consulEndpoint->post("/v3alpha/auth/authenticate",req);
    match response {
        http:Response resp => {
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    consulUrlValid = true;
                    var token = <string>jsonPayload.token;
                    match token {
                        string value => {
                            consulToken = untaint value;
                            consulAuthenticated = true;
                        }
                        error err => {
                            consulAuthenticated = false;
                        }
                    }
                }
                error err => {
                    string errorMessage = err.message;
                    if(errorMessage.contains("Connection refused"))
                    {
                        consulUrlValid = false;
                    }
                }
            }
        }
        error err => {
            log:printError(err.message, err = err);
        }
    }

    return consulAuthenticated;
}
