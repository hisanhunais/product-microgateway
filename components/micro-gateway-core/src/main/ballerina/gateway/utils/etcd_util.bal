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

public map etcdUrls;
public map urlChanged;
map defaultUrls;
string etcdToken;
boolean etcdPeriodicQueryInitialized = false;
public boolean etcdConnectionEstablished = false;
boolean etcdConnectionAttempted = false;
boolean credentialsProvided = false;
boolean etcdAuthenticationEnabled = true;
task:Timer? etcdTimer;
string etcdKVBasePath = "/v3alpha/kv";
string etcdAuthBasePath = "/v3alpha/auth";

@Description {value:"Setting up etcd timer task"}
public function initiateEtcdTimerTask()
{
    int etcdTriggerTime = config:getAsInt("etcdtimer", default = DEFAULT_ETCD_TRIGGER_TIME);
    (function() returns error?) onTriggerFunction = etcdTimerTask;
    function(error) onErrorFunction = etcdError;
    etcdTimer = new task:Timer(onTriggerFunction, onErrorFunction, etcdTriggerTime, delay = 1000);
    etcdTimer.start();
    printInfo(KEY_ETCD_UTIL, "Etcd Periodic Timer Task Started");
}

@Description {value:"Periodic Etcd Query. Trigger function of etcd timer task"}
public function etcdTimerTask() returns error? {
    if(etcdUrls.count() > 0)
    {
        foreach k, v in etcdUrls {

            string currentUrl = <string>v;
            string fetchedUrl = etcdLookup(<string>k);

            if(currentUrl != fetchedUrl)
            {
                etcdUrls[<string>k] = fetchedUrl;
                urlChanged[<string>k] = true;
            }
        }
        io:println(etcdUrls);
    }
    else
    {
        printInfo(KEY_ETCD_UTIL, "No Etcd keys provided. Stopping etcd periodic call");
        etcdTimer.stop();
    }

    return ();
}

@Description {value:"Error function of etcd timer task"}
public function etcdError(error e) {
    printError(KEY_ETCD_UTIL, "Etcd Timer Task failed");
}

@Description {value:"Setting up etcd requirements"}
public function etcdSetup(string key, string default, string configKey) returns string
{
    string endpointUrl;

    if(!etcdConnectionAttempted)
    {
        establishEtcdConnection();
        etcdConnectionAttempted = true;
    }

    if(etcdConnectionEstablished)
    {
        if(!etcdPeriodicQueryInitialized)
        {
            etcdPeriodicQueryInitialized = true;
            initiateEtcdTimerTask();
        }
        string etcdKey = retrieveConfig(configKey, "");

        if(etcdKey == "")
        {
            printInfo(KEY_ETCD_UTIL, "Etcd Key not provided for: " + key);
            endpointUrl = retrieveConfig(key, default);
        }
        else
        {
            defaultUrls[etcdKey] = default;
            urlChanged[etcdKey] = false;
            etcdUrls[etcdKey] = etcdLookup(etcdKey);
            endpointUrl = <string>etcdUrls[etcdKey];
        }
    }
    else
    {
        endpointUrl = retrieveConfig(key, default);
    }

    return endpointUrl;
}

@Description {value:"Establish etcd connection by authenticating etcd"}
public function establishEtcdConnection()
{
    string etcdurl = retrieveConfig("etcdurl", "");
    if(etcdurl != "")
    {
        etcdAuthenticate();
    }
    else
    {
        printError(KEY_ETCD_UTIL, "Etcd URL not provided");
        etcdConnectionEstablished = false;
    }
}

@Description {value:"Query etcd passing the key and retrieves value"}
public function etcdLookup(string key10) returns string
{
    string key64;
    string value64;
    string endpointUrl;
    http:Request req;

    var key = key10.base64Encode(charset = "utf-8");
    match key {
        string matchedKey => key64 = matchedKey;
        error err => printError(KEY_ETCD_UTIL, err.message);
    }

    req.setPayload({"key": untaint key64});

    if(etcdAuthenticationEnabled)
    {
        req.setHeader("Authorization", etcdToken);
    }

    var response = etcdEndpoint->post(etcdKVBasePath + "/range", req);
    match response {
        http:Response resp => {
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    var val64 = <string>jsonPayload.kvs[0].value;
                    match val64 {
                        string matchedValue => value64 = matchedValue;
                        error err => { value64 = "Not found"; }
                    }
                }
                error err => {
                    printError(KEY_ETCD_UTIL, err.message);
                }
            }
        }
        error err => {
            printError(KEY_ETCD_UTIL, err.message);
            value64 = "Not found";
        }
    }

    if(value64 == "Not found")
    {
        endpointUrl = <string>defaultUrls[key10];
    }
    else
    {
        var value10 = value64.base64Decode(charset = "utf-8");
        match value10 {
            string matchedValue10 => endpointUrl = untaint matchedValue10;
            error err => printError(KEY_ETCD_UTIL, err.message);
        }
    }
    return endpointUrl;
}

@Description {value:"Authenticate etcd by providing username and password and retrieve etcd token"}
public function etcdAuthenticate()
{
    http:Request req;

    string username = retrieveConfig("etcdusername", "");
    string password = retrieveConfig("etcdpassword", "");

    if(username == "" && password == "")
    {
        credentialsProvided = false;
    }
    else
    {
        credentialsProvided = true;
    }

    req.setPayload({ "name": untaint username, "password": untaint password });

    var response = etcdEndpoint->post(etcdAuthBasePath + "/authenticate", req);
    match response {
        http:Response resp => {
            var msg = resp.getJsonPayload();
            match msg {
                json jsonPayload => {
                    if(jsonPayload.token!= null)
                    {
                        var token = <string>jsonPayload.token;
                        match token {
                            string value => {
                                etcdToken = untaint value;
                                etcdConnectionEstablished = true;
                                printInfo(KEY_ETCD_UTIL, "Etcd Authentication Successful");
                            }
                            error err => {
                                etcdConnectionEstablished = false;
                                printError(KEY_ETCD_UTIL, err.message);
                            }
                        }
                    }
                    if(jsonPayload.error!=null)
                    {
                        var authenticationError = <string>jsonPayload.error;
                        match authenticationError {
                            string value => {
                                if(value.contains("authentication is not enabled"))
                                {
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
                }
                error err => {
                    printError(KEY_ETCD_UTIL, err.message);
                    etcdConnectionEstablished = false;
                }
            }
        }
        error err => {
            printError(KEY_ETCD_UTIL, err.message);
            etcdConnectionEstablished = false;
        }
    }
}