import shutil
from faster_whisper import download_model

out = download_model("small")  # WHISPER_MODEL 값과 동일해야 함
shutil.make_archive("data/cache/whisper-small", "gztar", out)

out = download_model("medium")
shutil.make_archive("data/cache/whisper-medium", "gztar", out)

out = download_model("base")
shutil.make_archive("data/cache/whisper-base", "gztar", out)

out = download_model("large-v3")
shutil.make_archive("data/cache/whisper-large-v3", "gztar", out)