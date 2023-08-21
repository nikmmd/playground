# Useful playbooks I run based on the structure in Christian Lempa's boliulerplate I liked 
- https://www.youtube.com/watch?v=NyOSoLn5T5U&t=922s


# Locally

```
ansible-playbook playbook.yaml -i ../inventory/hosts.ini

# For general hosts notebooks (e.g. BYOH (Bring your own host))

E.g. mainstance
cd playbooks/maintnance
ansible-playbook playbook.yaml -i ../../inventory/hosts.ini -e "hosts=all"
```



