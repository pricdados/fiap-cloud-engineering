import os
import json
import boto3

from aws_lambda_powertools import Logger, Metrics, Tracer
from aws_lambda_powertools.metrics import MetricUnit

# Observabilidade com Powertools — o mesmo padrao que voce viu na demo de Lambda
# (03.3): log estruturado (Logger), metrica de negocio via EMF (Metrics) e trace
# distribuido no X-Ray (Tracer). Ja vem pronto; voce nao precisa mexer aqui.
logger = Logger(service="pedeja-processa")
metrics = Metrics(namespace="PedeJaTF", service="pedeja-processa")
tracer = Tracer(service="pedeja-processa")

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_DATA_LAKE"]

# Prefixos no data lake: de onde le (raw/) e onde grava o resultado (resumo/).
PREFIXO_RAW = "raw/"
CHAVE_RESUMO = "resumo/faturamento.json"


@tracer.capture_method
def ler_pedidos_do_s3():
    """Le TODOS os pedidos crus em raw/ e devolve como lista de dicts.

    Ja esta pronto: pagina o bucket, baixa cada objeto .json e faz o parse.
    Voce recebe uma lista de pedidos como este:
        {"pedido_id": "PED-0001", "cidade": "Sao Paulo", "valor": 89.9, ...}
    """
    pedidos = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix=PREFIXO_RAW):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith(".json"):
                continue
            corpo = s3.get_object(Bucket=BUCKET, Key=obj["Key"])["Body"].read()
            pedidos.append(json.loads(corpo))
    logger.info("pedidos lidos do data lake", total=len(pedidos))
    return pedidos


@tracer.capture_method
def gravar_resumo_no_s3(resumo):
    """Grava o resumo agregado em resumo/faturamento.json. Ja esta pronto."""
    s3.put_object(
        Bucket=BUCKET,
        Key=CHAVE_RESUMO,
        Body=json.dumps(resumo, ensure_ascii=False, indent=2).encode("utf-8"),
        ContentType="application/json",
    )
    logger.info("resumo gravado", s3_key=CHAVE_RESUMO, cidades=len(resumo))


@logger.inject_lambda_context
@metrics.log_metrics
@tracer.capture_lambda_handler
def handler(event, context):
    pedidos = ler_pedidos_do_s3()

    # =====================================================================
    # TODO — VOCE COMPLETA AQUI (bloco 2: processar)
    # ---------------------------------------------------------------------
    # Voce recebe a lista `pedidos` (cada item tem "cidade" e "valor").
    # Monte o dicionario `resumo` agregando o faturamento por cidade, no
    # formato:
    #     resumo = {
    #         "Sao Paulo":      {"pedidos": 4, "faturamento": 235.30},
    #         "Rio de Janeiro": {"pedidos": 2, "faturamento": 198.40},
    #         ...
    #     }
    # Dica: percorra `pedidos`, some `valor` por `cidade` e conte quantos.
    # Arredonde o faturamento para 2 casas (round(x, 2)).
    #
    # Substitua a linha abaixo pela sua agregacao:
    resumo = {}
    # =====================================================================

    gravar_resumo_no_s3(resumo)

    # Metrica de negocio por cidade (aparece no CloudWatch via EMF). Ja pronto:
    # so roda se o seu `resumo` tiver o formato esperado acima.
    for cidade, dados in resumo.items():
        metrics.add_dimension(name="cidade", value=cidade)
        metrics.add_metric(name="faturamento_cidade", unit="None",
                           value=dados["faturamento"])

    return {"status": "ok", "cidades": len(resumo), "s3_key": CHAVE_RESUMO}
