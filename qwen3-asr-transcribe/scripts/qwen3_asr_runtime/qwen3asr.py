import os
import random
import time

import dashscope
from pydub import AudioSegment


MAX_API_RETRY = 10
API_RETRY_SLEEP = (1, 2)


LANGUAGE_CODE_MAPPING = {
    "ar": "Arabic",
    "zh": "Chinese",
    "en": "English",
    "fr": "French",
    "de": "German",
    "it": "Italian",
    "ja": "Japanese",
    "ko": "Korean",
    "pt": "Portuguese",
    "ru": "Russian",
    "es": "Spanish",
}


class QwenASR:
    def __init__(self, model: str = "qwen3-asr-flash"):
        self.model = model

    def post_text_process(self, text: str, threshold: int = 20) -> str:
        def fix_char_repeats(value: str, repeat_threshold: int) -> str:
            result = []
            index = 0
            length = len(value)
            while index < length:
                count = 1
                while index + count < length and value[index + count] == value[index]:
                    count += 1
                if count > repeat_threshold:
                    result.append(value[index])
                else:
                    result.append(value[index : index + count])
                index += count
            return "".join(result)

        def fix_pattern_repeats(value: str, repeat_threshold: int, max_len: int = 20) -> str:
            length = len(value)
            min_repeat_chars = repeat_threshold * 2
            if length < min_repeat_chars:
                return value

            index = 0
            result = []
            while index <= length - min_repeat_chars:
                found = False
                for pattern_len in range(1, max_len + 1):
                    if index + pattern_len * repeat_threshold > length:
                        break
                    pattern = value[index : index + pattern_len]
                    valid = True
                    for repeat_index in range(1, repeat_threshold):
                        start_idx = index + repeat_index * pattern_len
                        if value[start_idx : start_idx + pattern_len] != pattern:
                            valid = False
                            break
                    if not valid:
                        continue
                    end_index = index + repeat_threshold * pattern_len
                    while end_index + pattern_len <= length and value[end_index : end_index + pattern_len] == pattern:
                        end_index += pattern_len
                    result.append(pattern)
                    result.append(fix_pattern_repeats(value[end_index:], repeat_threshold, max_len))
                    index = length
                    found = True
                    break
                if found:
                    break
                result.append(value[index])
                index += 1

            if index < length:
                result.append(value[index:])
            return "".join(result)

        text = fix_char_repeats(text, threshold)
        return fix_pattern_repeats(text, threshold)

    def asr(self, wav_url: str, context: str = "") -> tuple[str, str]:
        if not wav_url.startswith("http"):
            if not os.path.exists(wav_url):
                raise FileNotFoundError(f"Input media does not exist: {wav_url}")

            file_size = os.path.getsize(wav_url)
            if file_size > 10 * 1024 * 1024:
                mp3_path = os.path.splitext(wav_url)[0] + ".mp3"
                audio = AudioSegment.from_file(wav_url)
                audio.export(mp3_path, format="mp3")
                wav_url = mp3_path

            wav_url = f"file://{wav_url}"

        last_error = None
        last_response = None
        for attempt in range(MAX_API_RETRY):
            try:
                response = dashscope.MultiModalConversation.call(
                    model=self.model,
                    messages=[
                        {
                            "role": "system",
                            "content": [{"text": context}],
                        },
                        {
                            "role": "user",
                            "content": [{"audio": wav_url}],
                        },
                    ],
                    result_format="message",
                    asr_options={
                        "enable_lid": True,
                        "enable_itn": False,
                    },
                )
                last_response = response

                if response.status_code != 200:
                    raise RuntimeError(f"http status_code: {response.status_code} {response}")

                output = response["output"]["choices"][0]
                recog_text = ""
                if output["message"]["content"]:
                    recog_text = output["message"]["content"][0].get("text", "") or ""

                lang_code = None
                if "annotations" in output["message"]:
                    lang_code = output["message"]["annotations"][0].get("language")
                language = LANGUAGE_CODE_MAPPING.get(lang_code, "Not Supported")
                return language, self.post_text_process(recog_text)
            except Exception as exc:
                last_error = exc
                try:
                    if getattr(last_response, "code", None) == "DataInspectionFailed":
                        raise RuntimeError(f"Invalid input audio for DashScope: {wav_url}") from exc
                except Exception:
                    pass
                if attempt < MAX_API_RETRY - 1:
                    time.sleep(random.uniform(*API_RETRY_SLEEP))

        raise RuntimeError(f"ASR task failed for {wav_url}: {last_error or last_response}")
