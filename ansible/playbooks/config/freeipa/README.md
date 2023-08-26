# Intro

I run a [freeipa server](https://www.freeipa.org/) and I like to easily have my Proxmox cluster VMs join a domain to avoid copying cloudinit templates, ssh keys, user maps, groups and other things.
IPA really simplifies this + is a nice centrailized directory service for users, sudo rules, policies for Linux. Host to dns automapping is also nice if you use Freeipa as your DNS server. 

This playbook is meant to 1) be run standalone targeting freshly created hosts or 2) as a cloudinit step via ansible localhost provisioner. I prefer running this playbook on a VM's localhost provisioner, cause then everything can be done unattended.

Refs:
 - https://bgstack15.wordpress.com/2020/01/15/freeipa-service-account-to-join-systems-unattended/
 - 

## cmd

- Enroll

ansible-playbook enroll.yml -i ../../../inventory/hosts.ini -e "@../../../inventory/vars/ipa.yml"


- Unenroll

ansible-playbook unenroll.yml -i ../../../inventory/hosts.ini -e "@../../../inventory/vars/ipa.yml"




## Vars

```
server: <your.ipa.server>
domain: <your.ipa.domain>
realm: <YOUR.KERBEROS.REALM>
enrollment_principal: <enroller-user>
enrollment_password: <enroller-password>

ipa_client_ansible_hosts: <clients to enroll/unenroll host groups from hosts.ini/hosts.yml>
ipa_server_ansible_hosts: <ipa server host groups from hosts.ini/hosts.yml>


kerberos_user: <ipa server user that can run cmds>
kerberos_password:: <ipa server user password that can run cmds>

```

## Defaults:

```
ipaclient_reboot_after: true
```