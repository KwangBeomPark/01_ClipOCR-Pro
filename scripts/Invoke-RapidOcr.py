#!/usr/bin/env python3
"""Offline local RapidOCR runner invoked by ClipOCR-Pro."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys

DET_MODEL_NAME = "ch_PP-OCRv5_det_mobile.onnx"
KOREAN_REC_MODEL = "korean_PP-OCRv5_rec_mobile.onnx"
LATIN_REC_MODEL = "latin_PP-OCRv5_rec_mobile.onnx"
REQUIRED_RAPIDOCR_VERSION = "3.10.0"
REQUIRED_ONNXRUNTIME_VERSION = "1.32.0"
APPROVED_MODEL_SHA256 = {
    DET_MODEL_NAME: "4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae",
    KOREAN_REC_MODEL: "cd6e2ea50f6943ca7271eb8c56a877a5a90720b7047fe9c41a2e541a25773c9b",
    LATIN_REC_MODEL: "b20bd37c168a570f583afbc8cd7925603890efbcdc000a59e22c269d160b5f5a",
}


def verify_runtime_versions() -> bool:
    import importlib.metadata as importlib_metadata

    try:
        rapidocr_ver = importlib_metadata.version("rapidocr")
        onnxruntime_ver = importlib_metadata.version("onnxruntime")
    except importlib_metadata.PackageNotFoundError:
        return False
    return (
        rapidocr_ver == REQUIRED_RAPIDOCR_VERSION
        and onnxruntime_ver == REQUIRED_ONNXRUNTIME_VERSION
    )
LATIN_BASE_LANGUAGES = frozenset({
    "en", "pl", "de", "fr", "es", "it", "pt", "nl", "cs", "sk", "hu", "ro",
    "tr", "vi", "id", "ms", "sv", "da", "no", "nb", "nn", "fi", "hr", "sl",
    "lt", "lv", "et",
})


def write_status(status_path: str, state: str, code: str, message: str) -> None:
    safe_message = re.sub(r"[\r\n|]+", " ", str(message)).strip()
    with open(status_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(f"{state}|{code}|{safe_message}")


def write_output(output_path: str, text: str) -> None:
    with open(output_path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def is_nonempty_file(path: str) -> bool:
    try:
        return os.path.isfile(path) and os.path.getsize(path) > 0
    except OSError:
        return False


def file_sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(65536):
            digest.update(chunk)
    return digest.hexdigest().lower()


def verify_model_checksum(path: str, filename: str) -> bool:
    expected = APPROVED_MODEL_SHA256.get(filename)
    if not expected or not is_nonempty_file(path):
        return False
    return file_sha256(path) == expected


def has_embedded_character_metadata(model_path: str) -> bool:
    import onnxruntime as ort

    sess = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    try:
        meta = sess.get_modelmeta().custom_metadata_map
        chars = meta.get("character", "")
        return bool(str(chars).strip())
    finally:
        del sess


def select_rec_model(models_dir: str, languages_arg: str) -> tuple[str, str, str, str] | None:
    korean_path = os.path.join(models_dir, KOREAN_REC_MODEL)
    latin_path = os.path.join(models_dir, LATIN_REC_MODEL)
    for raw_tag in languages_arg.split(","):
        tag = raw_tag.strip()
        if not tag:
            continue
        base_lang = tag.split("-", 1)[0].lower()
        if base_lang == "ko" and is_nonempty_file(korean_path):
            return base_lang, "korean", korean_path, KOREAN_REC_MODEL
        if base_lang in LATIN_BASE_LANGUAGES and is_nonempty_file(latin_path):
            return base_lang, "latin", latin_path, LATIN_REC_MODEL
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline RapidOCR runner for ClipOCR-Pro.")
    parser.add_argument("--image", required=True)
    parser.add_argument("--lang", required=True)
    parser.add_argument("--models-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--status", required=True)
    args = parser.parse_args()

    try:
        if not os.path.isfile(args.image):
            write_status(args.status, "ERROR", "NO_IMAGE", "Image file was not found.")
            return 1

        if not os.path.isdir(args.models_dir):
            write_status(args.status, "ERROR", "NO_MODELS", "RapidOCR models directory was not found.")
            return 3

        det_model = os.path.join(models_dir := args.models_dir, DET_MODEL_NAME)
        if not is_nonempty_file(det_model):
            write_status(args.status, "ERROR", "NO_MODELS", f"Missing required detection model: {DET_MODEL_NAME}")
            return 3

        selection = select_rec_model(models_dir, args.lang)
        if selection is None:
            write_status(
                args.status,
                "ERROR",
                "NO_LANGUAGE",
                "RapidOCR model for requested language is not installed.",
            )
            return 2

        selected_base_lang, rec_kind, rec_model, rec_filename = selection

        if not verify_model_checksum(det_model, DET_MODEL_NAME) or not verify_model_checksum(rec_model, rec_filename):
            write_status(
                args.status,
                "ERROR",
                "INVALID_MODEL",
                "RapidOCR model checksum verification failed.",
            )
            return 3

        if not verify_runtime_versions():
            write_status(
                args.status,
                "ERROR",
                "INVALID_RUNTIME",
                f"Unsupported RapidOCR/ONNXRuntime version (requires rapidocr=={REQUIRED_RAPIDOCR_VERSION}, onnxruntime=={REQUIRED_ONNXRUNTIME_VERSION}).",
            )
            return 3

        if not has_embedded_character_metadata(rec_model):
            write_status(
                args.status,
                "ERROR",
                "INVALID_MODEL",
                "Recognition model lacks embedded character dictionary metadata.",
            )
            return 3

        from PIL import Image, ImageOps
        from rapidocr import EngineType, LangDet, LangRec, ModelType, OCRVersion, RapidOCR

        with Image.open(args.image) as opened:
            transposed = ImageOps.exif_transpose(opened)
            if transposed.mode in ("RGBA", "LA", "PA") or (
                transposed.mode == "P" and "transparency" in transposed.info
            ):
                pil_image = transposed.convert("RGBA")
            else:
                pil_image = transposed.convert("RGB")

        params = {
            "Global.use_det": True,
            "Global.use_cls": False,
            "Global.use_rec": True,
            "Global.min_height": 10,
            "Global.width_height_ratio": -1,
            "Global.log_level": "error",
            "Det.engine_type": EngineType.ONNXRUNTIME,
            "Det.lang_type": LangDet.CH,
            "Det.model_type": ModelType.MOBILE,
            "Det.ocr_version": OCRVersion.PPOCRV5,
            "Det.model_path": det_model,
            "Det.limit_type": "max",
            "Det.limit_side_len": 1600,
            "Det.box_thresh": 0.3,
            "Rec.engine_type": EngineType.ONNXRUNTIME,
            "Rec.lang_type": LangRec.KOREAN if rec_kind == "korean" else LangRec.LATIN,
            "Rec.model_type": ModelType.MOBILE,
            "Rec.ocr_version": OCRVersion.PPOCRV5,
            "Rec.model_path": rec_model,
        }
        engine = RapidOCR(params=params)
        result = engine(pil_image)

        raw_txts = getattr(result, "txts", None) or ()
        lines = [str(line) for line in raw_txts if str(line).strip()]
        write_output(args.output, "\r\n".join(lines))
        write_status(args.status, "OK", selected_base_lang, "RapidOCR PP-OCRv5")
        return 0
    except Exception as exc:
        write_status(args.status, "ERROR", "EXCEPTION", str(exc) or exc.__class__.__name__)
        return 1


if __name__ == "__main__":
    sys.exit(main())
