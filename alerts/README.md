# README #

This README would normally document whatever steps are necessary to get your application up and running.

### What is this repository for? ###

* Quick summary
* Version
* [Learn Markdown](https://bitbucket.org/tutorials/markdowndemo)

### How do I get set up? ###

* Summary of set up
* Configuration

Alert rules and configs

- Alerts(aka PrometheusRules CRDs) that should only exist for Observability clusters must be located here at alertmanager-rules directory.
Generic Alerts for Infrastructure related services should derive from sitecore.platform.alerting.infrastructure repository. Here we need to 
focus only on Observability cluster-only alerts, like the ones for redislabs of selfhosted redis instances.

- Alert Configuration(aka AlertManagerConfig CRDs) that should only exist for Observability clusters must be located here at alertmanager-config directory
TODO: current 2 yamls are not valid, they are placeholders, have to fix them.


So if we have redislabs and selfhosted redis instances, we end up with alerts that can be triggered for each case. For 2 alerts we want them to be sent only 
to infra team. So how many AlertmanagerConfig CRD would we end up needing? 4?
* Dependencies

monitoring-stack kustomization(The one that deploys Prometheus & Alertmanager through sitecore.platform.fleet.infrastructure.monitoring) is a dependency
and must pre-exist

* Database configuration
* How to run tests
* Deployment instructions

### Contribution guidelines ###

* Writing tests
* Code review
* Other guidelines

### Who do I talk to? ###

* Repo owner or admin
* Other community or team contact