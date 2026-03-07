import json
import re

from transformers import Qwen2_5_VLForConditionalGeneration, AutoTokenizer, AutoProcessor
from qwen_vl_utils import process_vision_info

# default: Load the model on the available device(s)
model = Qwen2_5_VLForConditionalGeneration.from_pretrained(
    "Qwen/Qwen2.5-VL-7B-Instruct", torch_dtype="auto", device_map="auto"
)

processor = AutoProcessor.from_pretrained("Qwen/Qwen2.5-VL-7B-Instruct")

### Customization Prompt

prompt = """
You are a data extraction system.

Extract these fields from the image:
- name_cn
- name_pinyin : 名字拼音，请合理参考中文名字。如果中文名字是孙建芬 格式应为 "Sun, JianFen"。姓在前，名在后，如果名字是多字，每个字拼音的第一个字母大写。
- birthday (YYYY-MM-DD)
- baptism_date (YYYY-MM-DD)
- phone : 连续10位数字
- address : 请变为正确的地址格式
- birth : "来自省份"

Return json only. Put null at appropriate places.
"""

def parse_ocr(image_path: str) -> dict:
    messages = [
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "image": image_path,
                },
                {"type": "text", "text": prompt},
            ],
        }
    ]

    text = processor.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    image_inputs, video_inputs = process_vision_info(messages)
    inputs = processor(
        text=[text],
        images=image_inputs,
        videos=video_inputs,
        padding=True,
        return_tensors="pt",
    )
    inputs = inputs.to("cuda")

    # Inference: Generation of the output
    generated_ids = model.generate(**inputs, max_new_tokens=128)
    generated_ids_trimmed = [
        out_ids[len(in_ids) :] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
    ]
    output_text = processor.batch_decode(
        generated_ids_trimmed, skip_special_tokens=True, clean_up_tokenization_spaces=False
    )
    
    match = re.search(r"\{.*\}", output_text[0], re.S)
    if match:
        json_str = match.group(0)
        try:
            return json.loads(json_str)
        except json.JSONDecodeError as e:
            print(f"JSON decode error: {e}")
            return {}
    else:
        print("No JSON found in the output.")
        return {}
