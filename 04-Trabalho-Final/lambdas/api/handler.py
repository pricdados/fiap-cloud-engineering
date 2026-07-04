import os
import json
import boto3

from aws_lambda_powertools import Logger, Tracer

logger = Logger(service="pedeja-api")
tracer = Tracer(service="pedeja-api")

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_DATA_LAKE"]
CHAVE_RESUMO = "resumo/faturamento.json"


def resposta(status, corpo):
    """Monta a resposta HTTP no formato que o API Gateway espera. Ja pronto."""
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(corpo, ensure_ascii=False),
    }


@logger.inject_lambda_context
@tracer.capture_lambda_handler
def handler(event, context):
    # A API Gateway (proxy) invoca esta Lambda com um EVENTO — nao ha porta
    # escutando. Aqui respondemos GET /faturamento lendo o resumo do S3.

    # =====================================================================
    # TODO — VOCE COMPLETA AQUI (bloco 3: servir)
    # ---------------------------------------------------------------------
    # Leia o objeto CHAVE_RESUMO do bucket BUCKET no S3 e faca o parse do
    # JSON para um dict chamado `faturamento`.
    # Dica: use s3.get_object(Bucket=..., Key=...)["Body"].read() e json.loads.
    # Se o objeto ainda nao existe (o bloco 2 nao rodou), o get_object lanca
    # a excecao s3.exceptions.NoSuchKey — capture-a e devolva resposta(404, ...)
    # com uma mensagem clara (assim a API nao quebra com erro 500).
    #
    # Esqueleto (complete os ...):
    #     try:
    #         corpo = s3.get_object(Bucket=..., Key=...)["Body"].read()
    #         faturamento = json.loads(corpo)
    #     except s3.exceptions.NoSuchKey:
    #         return resposta(404, {"erro": "resumo ainda nao gerado; rode o bloco 2"})
    #
    # Substitua a linha abaixo pela sua leitura:
    faturamento = {}
    # =====================================================================

    logger.info("faturamento servido", cidades=len(faturamento))
    return resposta(200, faturamento)
