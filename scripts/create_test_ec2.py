#!/usr/bin/env python3
"""
scripts/create_test_ec2.py

Sobe uma EC2 de teste (Ubuntu 22.04) pra validar o setup-platform: Security Group
liberando só 22/80/443, Elastic IP associado (evita o problema de IP mudar em
stop/start), user-data que já clona o repo e deixa pronto pra rodar bin/setup.sh.

Usa SEMPRE o profile "geotec" e a região "us-east-1" (regra do projeto, ver CLAUDE.md).

Requisitos:
    pip install boto3 --break-system-packages
    aws configure --profile geotec   (se ainda não configurado)

Uso:
    python3 scripts/create_test_ec2.py
    python3 scripts/create_test_ec2.py --key-name minha-chave --instance-type t3.small
    python3 scripts/create_test_ec2.py --repo-url https://github.com/SEU-USUARIO/setup-platform.git
    python3 scripts/create_test_ec2.py --terminate i-0123456789abcdef0   # derruba a instância de teste
"""
from __future__ import annotations

import argparse
import sys
import time

import boto3
from botocore.exceptions import ClientError

AWS_PROFILE = "geotec"
AWS_REGION = "us-east-1"

TAG_PROJECT = "setup-platform"
SG_NAME = "setup-platform-test-sg"
DEFAULT_INSTANCE_TYPE = "t3.small"  # min recomendado pelo projeto: 2GB/2vCPU -> t3.small folgado
UBUNTU_OWNER_ID = "099720109477"  # Canonical
UBUNTU_NAME_FILTER = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"


def session() -> boto3.Session:
    return boto3.Session(profile_name=AWS_PROFILE, region_name=AWS_REGION)


def find_ubuntu_ami(ec2) -> str:
    resp = ec2.describe_images(
        Owners=[UBUNTU_OWNER_ID],
        Filters=[
            {"Name": "name", "Values": [UBUNTU_NAME_FILTER]},
            {"Name": "state", "Values": ["available"]},
            {"Name": "architecture", "Values": ["x86_64"]},
            {"Name": "virtualization-type", "Values": ["hvm"]},
        ],
    )
    images = sorted(resp["Images"], key=lambda i: i["CreationDate"], reverse=True)
    if not images:
        raise RuntimeError("Nenhuma AMI Ubuntu 22.04 encontrada. Confira a região/profile.")
    return images[0]["ImageId"]


def default_vpc_id(ec2) -> str:
    resp = ec2.describe_vpcs(Filters=[{"Name": "isDefault", "Values": ["true"]}])
    if not resp["Vpcs"]:
        raise RuntimeError(
            "Nenhuma VPC default encontrada na conta/região. "
            "Passe --subnet-id explicitamente ou crie uma VPC primeiro."
        )
    return resp["Vpcs"][0]["VpcId"]


def default_subnet_id(ec2, vpc_id: str) -> str:
    resp = ec2.describe_subnets(
        Filters=[{"Name": "vpc-id", "Values": [vpc_id]}, {"Name": "default-for-az", "Values": ["true"]}]
    )
    if not resp["Subnets"]:
        raise RuntimeError("Nenhuma subnet default encontrada na VPC default.")
    return resp["Subnets"][0]["SubnetId"]


def ensure_security_group(ec2, vpc_id: str, my_ip_cidr: str | None) -> str:
    resp = ec2.describe_security_groups(
        Filters=[{"Name": "group-name", "Values": [SG_NAME]}, {"Name": "vpc-id", "Values": [vpc_id]}]
    )
    if resp["SecurityGroups"]:
        sg_id = resp["SecurityGroups"][0]["GroupId"]
        print(f"[OK] Security Group já existe: {sg_id}")
        return sg_id

    sg = ec2.create_security_group(
        GroupName=SG_NAME,
        Description="setup-platform - teste (22/80/443)",
        VpcId=vpc_id,
        TagSpecifications=[
            {"ResourceType": "security-group", "Tags": [{"Key": "Project", "Value": TAG_PROJECT}]}
        ],
    )
    sg_id = sg["GroupId"]

    ssh_cidr = my_ip_cidr or "0.0.0.0/0"
    if ssh_cidr == "0.0.0.0/0":
        print("[AVISO] SSH liberado para 0.0.0.0/0 (qualquer IP). Use --my-ip para restringir só ao seu IP.")

    ec2.authorize_security_group_ingress(
        GroupId=sg_id,
        IpPermissions=[
            {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": ssh_cidr}]},
            {"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
            {"IpProtocol": "tcp", "FromPort": 443, "ToPort": 443, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]},
        ],
    )
    print(f"[OK] Security Group criado: {sg_id} (22 restrito, 80/443 públicos)")
    return sg_id


def build_user_data(repo_url: str | None) -> str:
    clone_step = ""
    if repo_url:
        clone_step = f"""
git clone --depth 1 "{repo_url}" /opt/setup-platform || true
chmod +x /opt/setup-platform/bin/*.sh /opt/setup-platform/core/*.sh \\
  /opt/setup-platform/providers/aws/*.sh /opt/setup-platform/modules/*/*.sh 2>/dev/null || true
"""
    return f"""#!/bin/bash
set -e
apt-get update -y
apt-get install -y git curl
{clone_step}
echo "setup-platform pronto. Rode: sudo bash /opt/setup-platform/bin/setup.sh" > /etc/motd
"""


def create_instance(args: argparse.Namespace) -> None:
    sess = session()
    ec2 = sess.client("ec2")
    ec2r = sess.resource("ec2")

    print(f"[INFO] Profile: {AWS_PROFILE} | Região: {AWS_REGION}")

    ami_id = args.ami_id or find_ubuntu_ami(ec2)
    print(f"[INFO] AMI: {ami_id}")

    vpc_id = args.vpc_id or default_vpc_id(ec2)
    subnet_id = args.subnet_id or default_subnet_id(ec2, vpc_id)
    print(f"[INFO] VPC: {vpc_id} | Subnet: {subnet_id}")

    sg_id = ensure_security_group(ec2, vpc_id, args.my_ip)

    run_kwargs = dict(
        ImageId=ami_id,
        InstanceType=args.instance_type,
        MinCount=1,
        MaxCount=1,
        SubnetId=subnet_id,
        SecurityGroupIds=[sg_id],
        UserData=build_user_data(args.repo_url),
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": args.name},
                    {"Key": "Project", "Value": TAG_PROJECT},
                    {"Key": "Purpose", "Value": "teste-setup-platform"},
                ],
            }
        ],
        BlockDeviceMappings=[
            {
                "DeviceName": "/dev/sda1",
                "Ebs": {"VolumeSize": args.disk_gb, "VolumeType": "gp3", "DeleteOnTermination": True},
            }
        ],
        MetadataOptions={  # força IMDSv2 (o que o providers/aws/detect.sh espera)
            "HttpTokens": "required",
            "HttpEndpoint": "enabled",
        },
    )

    if args.key_name:
        run_kwargs["KeyName"] = args.key_name
    else:
        print("[AVISO] Nenhum --key-name informado. Sem par de chaves você só acessa via SSM Session Manager.")

    print("[INFO] Criando instância EC2...")
    instances = ec2r.create_instances(**run_kwargs)
    instance = instances[0]
    print(f"[OK] Instância criada: {instance.id}. Aguardando ficar 'running'...")

    instance.wait_until_running()
    instance.reload()

    print("[INFO] Alocando Elastic IP (evita o IP mudar em stop/start)...")
    eip = ec2.allocate_address(Domain="vpc", TagSpecifications=[
        {"ResourceType": "elastic-ip", "Tags": [{"Key": "Project", "Value": TAG_PROJECT}]}
    ])
    ec2.associate_address(InstanceId=instance.id, AllocationId=eip["AllocationId"])
    public_ip = eip["PublicIp"]

    print("\n" + "=" * 60)
    print("EC2 de teste pronta")
    print("=" * 60)
    print(f"Instance ID : {instance.id}")
    print(f"Elastic IP  : {public_ip}")
    print(f"AZ          : {instance.placement['AvailabilityZone']}")
    if args.key_name:
        print(f"SSH         : ssh -i {args.key_name}.pem ubuntu@{public_ip}")
    else:
        print(f"SSM         : aws ssm start-session --target {instance.id} --profile {AWS_PROFILE} --region {AWS_REGION}")
    print("\nDepois de conectar, rode:")
    print("  sudo bash /opt/setup-platform/bin/setup.sh   # se usou --repo-url")
    print("  # ou clone manualmente e rode bin/setup.sh")
    print("=" * 60)


def terminate_instance(instance_id: str) -> None:
    sess = session()
    ec2 = sess.client("ec2")

    addrs = ec2.describe_addresses(Filters=[{"Name": "instance-id", "Values": [instance_id]}])
    for addr in addrs.get("Addresses", []):
        print(f"[INFO] Liberando Elastic IP {addr['PublicIp']}...")
        try:
            ec2.disassociate_address(AssociationId=addr["AssociationId"])
        except ClientError:
            pass
        ec2.release_address(AllocationId=addr["AllocationId"])

    print(f"[INFO] Terminando instância {instance_id}...")
    ec2.terminate_instances(InstanceIds=[instance_id])
    print("[OK] Instância marcada para terminação (o EIP já foi liberado pra evitar cobrança ociosa).")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Sobe/derruba uma EC2 de teste para o setup-platform (profile geotec).")
    p.add_argument("--name", default="setup-platform-teste", help="Tag Name da instância")
    p.add_argument("--instance-type", default=DEFAULT_INSTANCE_TYPE)
    p.add_argument("--disk-gb", type=int, default=20)
    p.add_argument("--key-name", default=None, help="Key pair já existente na conta (opcional, senão use SSM)")
    p.add_argument("--my-ip", default=None, help="Seu IP em formato CIDR (ex: 200.1.2.3/32) para restringir o SSH")
    p.add_argument("--vpc-id", default=None)
    p.add_argument("--subnet-id", default=None)
    p.add_argument("--ami-id", default=None, help="Sobrescreve a busca automática da AMI Ubuntu 22.04")
    p.add_argument(
        "--repo-url",
        default=None,
        help="URL do repo Git do setup-platform, para já clonar via user-data (ex: https://github.com/voce/setup-platform.git)",
    )
    p.add_argument("--terminate", metavar="INSTANCE_ID", default=None, help="Derruba a instância de teste e libera o EIP")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.terminate:
            terminate_instance(args.terminate)
        else:
            create_instance(args)
    except ClientError as e:
        print(f"[ERRO] Chamada AWS falhou: {e}", file=sys.stderr)
        sys.exit(1)
    except RuntimeError as e:
        print(f"[ERRO] {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
