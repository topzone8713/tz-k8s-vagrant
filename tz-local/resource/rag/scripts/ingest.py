#!/usr/bin/env python3
"""
RAG 인덱서: MinIO raw/ -> 청킹 -> 임베딩(OpenAI 또는 Gemini) -> Qdrant rag_docs
env: EMBEDDING_PROVIDER=openai|gemini,
     OpenAI: OPENAI_API_KEY, EMBEDDING_MODEL
     Gemini: GEMINI_API_KEY(또는 GOOGLE_API_KEY), EMBEDDING_MODEL=gemini-embedding-001
     공통: MINIO_*, QDRANT_*, CHUNK_SIZE, CHUNK_OVERLAP
"""
import os
import sys
import uuid
import hashlib
from io import BytesIO

# 의존성: pip install minio qdrant-client openai pypdf
# Gemini 사용 시 추가: pip install google-genai
from minio import Minio
from qdrant_client import QdrantClient
from qdrant_client.http import models as qmodels
from pypdf import PdfReader

def get_env(name: str, default: str = "") -> str:
    v = os.environ.get(name, default).strip()
    return v

def require_env(name: str) -> str:
    v = get_env(name)
    if not v:
        print(f"Missing env: {name}", file=sys.stderr)
        sys.exit(1)
    return v

def chunk_text(text: str, size: int = 500, overlap: int = 50) -> list[str]:
    if not text or not text.strip():
        return []
    chunks = []
    start = 0
    text = text.replace("\r\n", "\n").strip()
    while start < len(text):
        end = start + size
        chunk = text[start:end]
        if chunk.strip():
            chunks.append(chunk.strip())
        start = end - overlap if overlap < size else end
    return chunks

def extract_text(data: bytes, key: str) -> str:
    ext = (key.split(".")[-1] or "").lower()
    if ext == "pdf":
        try:
            reader = PdfReader(BytesIO(data))
            return "\n".join(p.extract_text() or "" for p in reader.pages)
        except Exception as e:
            print(f"PDF error {key}: {e}", file=sys.stderr)
            return ""
    if ext in ("txt", "md", "text"):
        try:
            return data.decode("utf-8", errors="replace")
        except Exception as e:
            print(f"Decode error {key}: {e}", file=sys.stderr)
            return ""
    try:
        return data.decode("utf-8", errors="replace")
    except Exception:
        return ""

def embed_openai(chunks: list[str], model: str, api_key: str) -> list[list[float]]:
    from openai import OpenAI
    client = OpenAI(api_key=api_key)
    resp = client.embeddings.create(input=chunks, model=model)
    sorted_data = sorted(resp.data, key=lambda d: d.index)
    return [d.embedding for d in sorted_data]

def embed_gemini(chunks: list[str], model: str, api_key: str, output_dim: int = 1536) -> list[list[float]]:
    from google import genai
    from google.genai import types
    client = genai.Client(api_key=api_key)
    result = client.models.embed_content(
        model=model,
        contents=chunks,
        config=types.EmbedContentConfig(
            task_type="RETRIEVAL_DOCUMENT",
            output_dimensionality=output_dim,
        ),
    )
    # result.embeddings: list of Embedding; each has .values (or is iterable)
    out = []
    for e in result.embeddings:
        v = getattr(e, "values", e)
        out.append(list(v) if not isinstance(v, list) else v)
    return out

def main():
    provider = get_env("EMBEDDING_PROVIDER", "openai").lower()
    if provider not in ("openai", "gemini"):
        print(f"EMBEDDING_PROVIDER must be openai or gemini, got: {provider}", file=sys.stderr)
        sys.exit(1)

    endpoint = get_env("MINIO_ENDPOINT", "minio.devops.svc.cluster.local")
    port = int(get_env("MINIO_PORT", "9000"))
    use_ssl = get_env("MINIO_USE_SSL", "false").lower() == "true"
    access_key = require_env("MINIO_ACCESS_KEY")
    secret_key = require_env("MINIO_SECRET_KEY")
    bucket = get_env("MINIO_BUCKET", "rag-docs")
    prefix = get_env("MINIO_PREFIX", "raw/").rstrip("/") + "/"

    qdrant_host = get_env("QDRANT_HOST", "qdrant")
    qdrant_port = int(get_env("QDRANT_PORT", "6333"))
    collection = get_env("QDRANT_COLLECTION", "rag_docs")

    chunk_size = int(get_env("CHUNK_SIZE", "500"))
    chunk_overlap = int(get_env("CHUNK_OVERLAP", "50"))

    if provider == "openai":
        api_key = require_env("OPENAI_API_KEY")
        embedding_model = get_env("EMBEDDING_MODEL", "text-embedding-3-small")
        embed_fn = lambda c: embed_openai(c, embedding_model, api_key)
        print(f"Embedding: OpenAI {embedding_model}")
    else:
        api_key = get_env("GEMINI_API_KEY") or get_env("GOOGLE_API_KEY")
        if not api_key:
            print("Missing env: GEMINI_API_KEY or GOOGLE_API_KEY", file=sys.stderr)
            sys.exit(1)
        embedding_model = get_env("EMBEDDING_MODEL", "gemini-embedding-001")
        output_dim = int(get_env("EMBEDDING_DIM", "1536"))
        embed_fn = lambda c: embed_gemini(c, embedding_model, api_key, output_dim)
        print(f"Embedding: Gemini {embedding_model} (dim={output_dim})")

    minio_client = Minio(
        f"{endpoint}:{port}",
        access_key=access_key,
        secret_key=secret_key,
        secure=use_ssl,
    )
    qdrant_client = QdrantClient(host=qdrant_host, port=qdrant_port, check_compatibility=False)

    if not minio_client.bucket_exists(bucket):
        minio_client.make_bucket(bucket)
        print(f"Created bucket {bucket}.")

    # 컬렉션을 비우고 다시 생성: MinIO에서 삭제한 파일에 해당하는 벡터도 제거됨 (전체 동기화)
    try:
        qdrant_client.delete_collection(collection_name=collection)
        print(f"Deleted collection {collection}.")
    except Exception as e:
        print(f"Delete collection (may not exist): {e}")
    qdrant_client.create_collection(
        collection_name=collection,
        vectors_config=qmodels.VectorParams(size=1536, distance=qmodels.Distance.COSINE),
    )
    print(f"Created collection {collection}.")

    objects = list(minio_client.list_objects(bucket, prefix=prefix, recursive=True))
    if not objects:
        print(f"No objects under {bucket}/{prefix}. Collection is empty. Upload PDF/txt then re-run.")
        sys.exit(0)

    points_to_upsert = []
    for obj in objects:
        key = obj.object_name
        if key.endswith("/"):
            continue
        data = minio_client.get_object(bucket, key).read()
        text = extract_text(data, key)
        if not text.strip():
            continue
        chunks = chunk_text(text, size=chunk_size, overlap=chunk_overlap)
        if not chunks:
            continue
        try:
            vectors_ordered = embed_fn(chunks)
        except Exception as e:
            print(f"Embedding error for {key}: {e}", file=sys.stderr)
            continue

        base_id = hashlib.sha256(key.encode()).hexdigest()[:16]
        for i, (vec, ctext) in enumerate(zip(vectors_ordered, chunks)):
            point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{key}:{i}"))
            points_to_upsert.append(
                qmodels.PointStruct(
                    id=point_id,
                    vector=vec,
                    payload={
                        "doc_id": base_id,
                        "source": os.path.basename(key),
                        "path": key,
                        "chunk_index": i,
                        "text": ctext[:2000],
                        "created_at": obj.last_modified.isoformat() if obj.last_modified else "",
                    },
                )
            )
        print(f"  {key}: {len(chunks)} chunks")

    if not points_to_upsert:
        print("No points to upsert.")
        sys.exit(0)

    batch_size = 100
    for i in range(0, len(points_to_upsert), batch_size):
        batch = points_to_upsert[i : i + batch_size]
        qdrant_client.upsert(collection_name=collection, points=batch)
        print(f"Upserted {len(batch)} points (total so far: {min(i + batch_size, len(points_to_upsert))})")

    info = qdrant_client.get_collection(collection)
    print(f"Done. {collection} points_count={info.points_count}")

if __name__ == "__main__":
    main()
