package org.wso2.apimgt.gateway.cli.model.config;

public class ServiceDiscovery {
    private Boolean isEnabled = null;
    private Etcd etcd;
    private Consul consul;

    public boolean isEnabled() {
        return isEnabled;
    }

    public void setEnabled(boolean enabled) {
        isEnabled = enabled;
    }

    public Etcd getEtcd() {
        return etcd;
    }

    public void setEtcd(Etcd etcd) {
        this.etcd = etcd;
    }

    public Consul getConsul() {
        return consul;
    }

    public void setConsul(Consul consul) {
        this.consul = consul;
    }
}
