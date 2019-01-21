#Azure Pipelines Deployment Groups Tasks

A set of tasks to interact with Deployment Groups in Azure Pipelines.

## Add Machines

A task to add one or more machines to a Deployment Group. It accepts the following the parameters:

* Deployment Group Name: Name of the deployment group to add machines to. This should already exist.
* Access Token: A token with Deployment Group Read/Manage permissions that is used to add each machine to the deployment group.
* Project: The project which contains the deployment group. Defaults to the project containing the build or release.
* Machines: List of machines to add to the chosen deployment group. Should be a comma separate list of names, FQDNs or IP addresses.
* Admin Login: Username of a local admin on the target machines.
* Password: Password of the local admin account.
* Protocol: Protocol to use for connecting with the machines. Defaults to HTTP.
* Test Certificate: Indicates whether the certificate on the HTTPS endpoint is a test certificate, such as self signed.
