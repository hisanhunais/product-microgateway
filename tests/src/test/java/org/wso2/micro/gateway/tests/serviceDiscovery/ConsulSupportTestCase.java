/*
 * Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
 *
 * WSO2 Inc. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
package org.wso2.micro.gateway.tests.serviceDiscovery;

import com.ecwid.consul.v1.ConsulClient;
import org.testng.Assert;
import org.testng.annotations.AfterClass;
import org.testng.annotations.AfterMethod;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;
import org.wso2.micro.gateway.tests.common.BaseTestCase;
import org.wso2.micro.gateway.tests.common.CLIExecutor;
import org.wso2.micro.gateway.tests.common.KeyValidationInfo;
import org.wso2.micro.gateway.tests.common.MockAPIPublisher;
import org.wso2.micro.gateway.tests.common.MockHttpServer;
import org.wso2.micro.gateway.tests.common.model.API;
import org.wso2.micro.gateway.tests.common.model.ApplicationDTO;
import org.wso2.micro.gateway.tests.context.ServerInstance;
import org.wso2.micro.gateway.tests.context.Utils;
import org.wso2.micro.gateway.tests.util.HttpResponse;
import org.wso2.micro.gateway.tests.util.TestConstant;

import java.io.File;

public class ConsulSupportTestCase extends BaseTestCase{
    private String jwtTokenProd, jwtTokenSand, balPath, configPath;
    private String consulUrlParameter;
    private String consulTokenParameter;
    private String pizzaShackEndpointSandConfigValue;
    private String pizzaShackProdConfigValue;
    private String pizzaShackProdEtcdKey = "pizzashackprod";
    private String pizzaShackProdParameter;
    private String pizzaShackSandConfigValue;
    private String pizzaShackSandEtcdKey = "pizzashacksand";
    private String pizzaShackSandParameter;
    private String pizzaShackSandNewEndpoint = "https://localhost:9443/echo/newsand";
    private String consulTimerParameter;
    private String overridingEndpointParameter;
    private String servicePath = "/pizzashack/1.0.0/menu";
    private final static String INVALID_URL_AT_CONSUL_RESPONSE = "{\"fault\":{\"code\":\"101503\", \"message\":\"Runtime Error\", \"description\":\"URL defined at consul for key pizzashackprod is invalid\"}}";
    private String pizzaShackProdEndpoint = "https://localhost:9443/echo/prod";
    private String pizzaShackProdNewEndpoint = "https://localhost:9443/echo/newprod";
    private String pizzaShackSandEndpoint = "https://localhost:9443/echo/sand";
    private ConsulClient client;
    private String token = "mastertoken";

    @BeforeClass
    public void start() throws Exception {
        String label = "apimTestLabel";
        String project = "apimTestProject";
        //get mock APIM Instance
        MockAPIPublisher pub = MockAPIPublisher.getInstance();
        API api = new API();
        api.setName("PizzaShackAPI");
        api.setContext("/pizzashack");
        api.setProdEndpoint(getMockServiceURLHttp("/echo/prod"));
        api.setSandEndpoint(getMockServiceURLHttp("/echo/sand"));
        api.setVersion("1.0.0");
        api.setProvider("admin");
        //Register API with label
        pub.addApi(label, api);

        //Define application info
        ApplicationDTO application = new ApplicationDTO();
        application.setName("jwtApp");
        application.setTier("Unlimited");
        application.setId((int) (Math.random() * 1000));

        //Register a production token with key validation info
        KeyValidationInfo info = new KeyValidationInfo();
        info.setApi(api);
        info.setApplication(application);
        info.setAuthorized(true);
        info.setKeyType(TestConstant.KEY_TYPE_PRODUCTION);
        info.setSubscriptionTier("Unlimited");

        jwtTokenProd = getJWT(api, application, "Unlimited", TestConstant.KEY_TYPE_PRODUCTION, 3600);
        jwtTokenSand = getJWT(api, application, "Unlimited", TestConstant.KEY_TYPE_SANDBOX, 3600);

        //generate apis with CLI and start the micro gateway server
        CLIExecutor cliExecutor;

        microGWServer = ServerInstance.initMicroGwServer();
        String cliHome = microGWServer.getServerHome();

        boolean isOpen = Utils.isPortOpen(MOCK_SERVER_PORT);
        Assert.assertFalse(isOpen, "Port: " + MOCK_SERVER_PORT + " already in use.");
        mockHttpServer = new MockHttpServer(MOCK_SERVER_PORT);
        mockHttpServer.start();
        cliExecutor = CLIExecutor.getInstance();
        cliExecutor.setCliHome(cliHome);
        cliExecutor.generatePassingFlag(label, project, "consul-enable");

        balPath = CLIExecutor.getInstance().getLabelBalx(project);
        configPath = getClass().getClassLoader()
                .getResource("confs" + File.separator + "default-test-config.conf").getPath();

        prepareConfigValues();
        prepareCLIParameters();
        initializeConsulServer();
    }

    private void initializeConsulServer() {
        String consul_host = System.getenv("CONSUL_HOST");
        int consul_port = Integer.parseInt(System.getenv("CONSUL_PORT"));
        client = new ConsulClient(consul_host, consul_port);

        //add pizzashackprod and corresponding url to consul.
        client.setKVValue(pizzaShackProdEtcdKey, pizzaShackProdEndpoint, token, null);
        String consulUrl;

        consulUrl = "http://" + consul_host + ":" + String.valueOf(consul_port);
        String consulUrlConfigValue = "consulurl";
        consulUrlParameter =  consulUrlConfigValue + "=" + consulUrl;
    }

    private void prepareConfigValues() {
        String apiEndpointSuffix = "endpoint_0";
        String consulKeySuffix = "consulKey";
        String prodUrlType = "prod";
        String sandUrlType = "sand";
        String apiId = "4a731db3-3a76-4950-a2d9-9778fd73b31c";
        pizzaShackEndpointSandConfigValue = apiId + "_" + sandUrlType + "_" + apiEndpointSuffix;
        pizzaShackProdConfigValue = apiId + "_" + prodUrlType + "_" + consulKeySuffix;
        pizzaShackSandConfigValue = apiId + "_" + sandUrlType + "_" + consulKeySuffix;
    }

    private void prepareCLIParameters() {
        String consulTokenConfigValue = "token";
        String consulTimerConfigValue = "consultimer";
        String consulTimer = "1000";
        consulTokenParameter = consulTokenConfigValue + "=" + token;
        pizzaShackProdParameter = pizzaShackProdConfigValue + "=" + pizzaShackProdEtcdKey;
        pizzaShackSandParameter = pizzaShackSandConfigValue + "=" + pizzaShackSandEtcdKey;
        consulTimerParameter = consulTimerConfigValue + "=" + consulTimer;
        overridingEndpointParameter = pizzaShackEndpointSandConfigValue + "=" + pizzaShackSandNewEndpoint;
    }

    @Test(description = "Test Etcd Support Providing all correct arguments")
    public void testConsulSupport() throws Exception {

        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test prod endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenProd, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        retryPolicy(jwtTokenProd, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support by changing the api url at the etcd node")
    public void testConsulSupportApiUrlChanged() throws Exception {
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test prod endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenProd, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);

        //change the prod endpoint url at consul node
        client.setKVValue(pizzaShackProdEtcdKey, pizzaShackProdNewEndpoint, token, null);

        retryPolicy(jwtTokenProd, MockHttpServer.PROD_ENDPOINT_NEW_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support Providing all correct arguments but provided keys not defined in Etcd Node")
    public void testMissingKeysInConsul() throws Exception {
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //sandbox key is not present at etcd. So invoke the sandbox endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenSand, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.SAND_ENDPOINT_RESPONSE, 200);

        //add a new value to the relevant sandbox key in consul
        client.setKVValue(pizzaShackSandEtcdKey, pizzaShackSandNewEndpoint, token, null);

        retryPolicy(jwtTokenSand, MockHttpServer.SAND_ENDPOINT_NEW_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support without providing relevant etcd keys")
    public void testWithoutProvidingKeys() throws Exception {
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        retryPolicy(jwtTokenProd, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support when etcd authentication fails")
    public void testConsulAuthenticationFailure() throws Exception {
        String invalidtoken = "token=invalid";
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", invalidtoken, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test prod endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenProd, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support when incorrect Etcd URL is provided")
    public void testWithIncorrectConsulUrl() throws Exception {
        String incorrectconsulUrl = "etcdurl=http://127.0.0.1:8505";
        String[] args = { "--config", configPath, "-e", incorrectconsulUrl, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test prod endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenProd, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support without providing Etcd URL")
    public void testWithoutConsulUrl() throws Exception {
        String[] args = { "--config", configPath, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test the prod endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenProd, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.PROD_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support by changing the api url at the etcd node")
    public void testOverridingEndpointUrl() throws Exception {
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter, "-e", overridingEndpointParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //test sand endpoint
        HttpResponse response = Utils.invokeApi(jwtTokenSand, getServiceURLHttp(servicePath));
        Utils.assertResult(response, MockHttpServer.SAND_ENDPOINT_NEW_RESPONSE, 200);

        //change the sand endpoint url at consul node
        client.setKVValue(pizzaShackSandEtcdKey, pizzaShackSandEndpoint, token, null);

        retryPolicy(jwtTokenSand, MockHttpServer.SAND_ENDPOINT_RESPONSE, 200);
        microGWServer.stopServer(false);
    }

    @Test(description = "Test Etcd Support when the URL defined at etcd corresponding to a key is invalid")
    public void testInvalidUrlAtConsul() throws Exception {
        String[] args = { "--config", configPath, "-e", consulUrlParameter, "-e", consulTokenParameter, "-e", pizzaShackProdParameter, "-e", pizzaShackSandParameter, "-e", consulTimerParameter };
        microGWServer.startMicroGwServer(balPath, args);

        //insert an invalid url for the pizzashackprod key at etcd node
        String invalidUrlValue = "abcd";
        client.setKVValue(pizzaShackProdEtcdKey, invalidUrlValue, token, null);

        retryPolicy(jwtTokenProd, INVALID_URL_AT_CONSUL_RESPONSE, 500);
        microGWServer.stopServer(false);
    }

    private void retryPolicy(String token, String responseData, int responseCode) throws Exception {
        boolean testPassed = false;
        for (int retries = 0; retries < 5; retries++) {
            Utils.delay(1000);
            HttpResponse response = Utils.invokeApi(token, getServiceURLHttp(servicePath));
            if (response.getData().equals(responseData) && response.getResponseCode() == responseCode) {
                testPassed = true;
                break;
            }
        }

        if (!testPassed) {
            Assert.fail();
        }
    }

    @AfterMethod
    public void consulInitialState() {
        client.setKVValue(pizzaShackProdEtcdKey, pizzaShackProdEndpoint, token, null);
        client.deleteKVValue(pizzaShackSandEtcdKey, token);
    }

    @AfterClass
    public void stop() throws Exception {
        //Stop all the mock servers
        super.finalize();
    }
}
