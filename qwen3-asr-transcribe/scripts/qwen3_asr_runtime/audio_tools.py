import io
import os
import subprocess

import librosa
import numpy as np
import soundfile as sf
from silero_vad import get_speech_timestamps


WAV_SAMPLE_RATE = 16000


def load_audio(file_path: str) -> np.ndarray:
    try:
        if file_path.startswith(("http://", "https://")):
            raise ValueError("Use ffmpeg to load remote media.")
        wav_data, _ = librosa.load(file_path, sr=WAV_SAMPLE_RATE, mono=True)
        return wav_data
    except Exception:
        command = [
            "ffmpeg",
            "-i",
            file_path,
            "-ar",
            str(WAV_SAMPLE_RATE),
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            "-f",
            "wav",
            "-",
        ]
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdout_data, stderr_data = process.communicate()

        if process.returncode != 0:
            stderr_text = stderr_data.decode("utf-8", errors="ignore")
            raise RuntimeError(f"FFmpeg failed to decode media: {stderr_text}")

        with io.BytesIO(stdout_data) as data_io:
            wav_data, _ = sf.read(data_io, dtype="float32")
        return wav_data


def process_vad(
    wav: np.ndarray,
    worker_vad_model,
    segment_threshold_s: int = 120,
    max_segment_threshold_s: int = 180,
) -> list[tuple[int, int, np.ndarray]]:
    try:
        speech_timestamps = get_speech_timestamps(
            wav,
            worker_vad_model,
            sampling_rate=WAV_SAMPLE_RATE,
            return_seconds=False,
            min_speech_duration_ms=1500,
            min_silence_duration_ms=500,
        )

        if not speech_timestamps:
            raise ValueError("No speech segments detected by VAD.")

        potential_split_points = {0.0, len(wav)}
        for timestamp in speech_timestamps:
            potential_split_points.add(timestamp["start"])
        sorted_potential_splits = sorted(potential_split_points)

        final_split_points = {0.0, len(wav)}
        segment_threshold_samples = segment_threshold_s * WAV_SAMPLE_RATE
        target_time = segment_threshold_samples
        while target_time < len(wav):
            closest_point = min(sorted_potential_splits, key=lambda point: abs(point - target_time))
            final_split_points.add(closest_point)
            target_time += segment_threshold_samples
        final_ordered_splits = sorted(final_split_points)

        max_segment_threshold_samples = max_segment_threshold_s * WAV_SAMPLE_RATE
        bounded_split_points = [0.0]
        for index in range(1, len(final_ordered_splits)):
            start = final_ordered_splits[index - 1]
            end = final_ordered_splits[index]
            segment_length = end - start

            if segment_length <= max_segment_threshold_samples:
                bounded_split_points.append(end)
                continue

            num_subsegments = int(np.ceil(segment_length / max_segment_threshold_samples))
            subsegment_length = segment_length / num_subsegments
            for sub_index in range(1, num_subsegments):
                bounded_split_points.append(start + sub_index * subsegment_length)
            bounded_split_points.append(end)

        segments = []
        for index in range(len(bounded_split_points) - 1):
            start_sample = int(bounded_split_points[index])
            end_sample = int(bounded_split_points[index + 1])
            segments.append((start_sample, end_sample, wav[start_sample:end_sample]))
        return segments
    except Exception:
        segments = []
        max_chunk_size_samples = max_segment_threshold_s * WAV_SAMPLE_RATE
        for start_sample in range(0, len(wav), max_chunk_size_samples):
            end_sample = min(start_sample + max_chunk_size_samples, len(wav))
            segment = wav[start_sample:end_sample]
            if len(segment) > 0:
                segments.append((start_sample, end_sample, segment))
        return segments


def save_audio_file(wav: np.ndarray, file_path: str) -> None:
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    sf.write(file_path, wav, WAV_SAMPLE_RATE)
