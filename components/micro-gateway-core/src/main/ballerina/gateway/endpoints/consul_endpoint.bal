import ballerina/io;
import ballerina/http;
import ballerina/config;

endpoint http:Client consulEndpoint {
    url: retrieveConfig("consulurl", "http://127.0.0.1:8500")
};
