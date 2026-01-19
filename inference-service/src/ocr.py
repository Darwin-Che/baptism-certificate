import json
import re

import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

from paddleocr import PaddleOCRVL

######## OCR model

paddle_ocr_vl = PaddleOCRVL()

def extract_ocr(file):
    output = paddle_ocr_vl.predict(file)
    result = ""
    for res in output:
        for block in res['parsing_res_list']:
            result += block.content
            result += "\n"
    return result

####### LLM model

model_name = "Qwen/Qwen2.5-1.5B-Instruct"
# model_name = "/models/qwen2.5b"

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    torch_dtype=torch.float16,
    device_map="auto"
)

def parse_ocr(text):
    prompt = f"""
You are a data extraction system.

Extract these fields from the OCR text:
- name_cn
- name_pinyin : 名字拼音，请合理参考中文名字。如果中文名字是孙建芬 格式应为 "Sun JianFen"。姓在前，名在后，如果名字是多字，每个字拼音的第一个字母大写。
- birthday (YYYY-MM-DD)
- baptism_date (YYYY-MM-DD)
- phone : 连续10位数字
- address : 请变为正确的地址格式
- birth : "来自省份"

OCR text:
{text}

Return JSON only. Put null at appropriate places.
"""

    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)

    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=256,
            temperature=0.1,
            do_sample=False
        )

    result = tokenizer.decode(outputs[0], skip_special_tokens=True)

    # Extract JSON safely
    match = re.search(r"\{.*\}", result, re.S)
    if match:
        return json.loads(match.group())
    else:
        return result
