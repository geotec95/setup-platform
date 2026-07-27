---
description: Varredura de segurança do repositório inteiro (segredos, IAM, exposição de portas, hardening)
---

Delegue esta tarefa ao subagente `security-engineer` (`.claude/agents/security-engineer.md`). Responda sempre em português do Brasil.

Escopo da varredura:

1. **Segredos vazados**: grep por padrões de chave/senha hardcoded em `.sh`, `.yaml`, `.json`, `.env*` versionados (`AKIA`, `SECRET`, `PASSWORD=`, `password:`, tokens). Nenhum `.env` real (só `.env.example`) deveria estar commitado — confira `.gitignore`.
2. **IAM**: revise `providers/aws/iam-policy-*.json` — confirme que é least-privilege, sem `"Action": "*"` nem `"Resource": "*"` desnecessário.
3. **Rede**: grep por `0.0.0.0/0` em compose files, manifests e no `scripts/create_test_ec2.py` — toda porta liberada assim precisa de justificativa explícita (80/443 ok, o resto não).
4. **Exposição via Traefik**: confira que só serviços que DEVEM ter painel público têm `traefik.enable=true` — Prometheus/Loki nunca.
5. **Docker**: procure por `privileged: true`, montagem de `docker.sock` sem necessidade, containers rodando como root sem justificativa.
6. **AWS_PROFILE**: confirme que todo script/comando AWS no repo usa `AWS_PROFILE=geotec` / `us-east-1`, nunca profile default.

Ao final, entregue um relatório com achados classificados por severidade (crítico/alto/médio/baixo), cada um com o arquivo:linha e o fix sugerido. Se não achar nada, diga isso claramente.
