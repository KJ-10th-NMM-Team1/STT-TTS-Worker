# STT·TTS 워커

SQS 큐를 구독해 영상 더빙 파이프라인과 세그먼트별 오디오 리믹스를 수행하는 백엔드 워커입니다.

## 주요 역할

- **전체 파이프라인(`task=full_pipeline`)**
  - 입력 영상을 받아 트랙 분리 → STT → 번역 → TTS → BGM과 합성 → 결과 영상/메타데이터를 S3 `outputs/`에 저장하고 콜백 URL로 완료 상태 전송.
- **세그먼트 리믹스(`task=segment_mix` 또는 `task=tts_bgm_mix`)**
  - S3 `interim/`(intermediate) 영역에 저장된 세그먼트별 BGM·TTS 파일을 내려받아 볼륨을 조정하고 믹스 → `mix.wav`를 다시 업로드 → 작업 결과를 콜백으로 알림.
- 모든 단계에서 실패 시 `failed` 상태와 오류 메시지를 콜백으로 전송하여 Job Store에서 상태를 추적할 수 있게 합니다.

## 처리 흐름

1. **SQS 폴링**
   - `JOB_QUEUE_URL`에서 메시지를 하나씩 수신하고 JSON 파싱 후 `task` 값에 따라 분기합니다.
2. **작업 실행**
   - `full_pipeline`: `_handle_full_pipeline`에서 기존 AI 더빙 파이프라인을 그대로 수행합니다.
   - `segment_mix`: `_handle_segment_mix`에서 세그먼트 목록을 순회하며 FFmpeg `amix` 필터로 믹싱을 수행합니다.
3. **콜백 통지**
   - 진행 중 단계(`downloaded`, `tts_prepare`, `segment_mix_started`)와 완료 단계(`done`, `segment_mix_completed`)에서 콜백 URL로 상태를 POST합니다.
   - 예외 발생 시 `_safe_fail`을 통해 `failed` 상태를 전송합니다.

## S3 구조

| Prefix                                                               | 설명                                   |
| -------------------------------------------------------------------- | -------------------------------------- |
| `projects/{project_id}/inputs/`                                      | 원본 영상 업로드 경로                  |
| `projects/{project_id}/outputs/videos/{job_id}.mp4`                  | 최종 더빙 영상                         |
| `projects/{project_id}/outputs/metadata/{job_id}.json`               | 세그먼트·번역 정보를 포함한 메타데이터 |
| `projects/{project_id}/interim/{job_id}/segments/{index}_source.wav` | 세그먼트별 원본 발화 구간              |
| `projects/{project_id}/interim/{job_id}/segments/{index}_bgm.wav`    | 세그먼트별 배경/FX 트랙                |
| `projects/{project_id}/interim/{job_id}/segments/{index}_tts.wav`    | 세그먼트별 합성 음성                   |
| `projects/{project_id}/interim/{job_id}/segments/{index}_mix.wav`    | 세그먼트별 믹스 결과                   |
| `projects/{project_id}/interim/{job_id}/segments/{index}_video.mp4`  | 세그먼트별 무음 비디오 클립            |

> `segment_mix` 작업은 `bgm_key`/`tts_key`가 명시되지 않은 경우 `intermediate_prefix`를 기반으로 `{index}_bgm.wav`, `{index}_tts.wav`를 자동 유추합니다.

## SQS 메시지 예시

```json
// 전체 파이프라인
{
  "task": "full_pipeline",
  "job_id": "...",
  "project_id": "...",
  "input_key": "projects/123/inputs/videos/input.mp4",
  "callback_url": "https://api.example.com/api/jobs/{job_id}/status",
  "target_lang": "en",
  "source_lang": "ko"
}

// 세그먼트 리믹스
{
  "task": "segment_mix",
  "job_id": "...",
  "project_id": "...",
  "callback_url": "https://api.example.com/api/editor/jobs/{job_id}/status",
  "intermediate_prefix": "projects/123/interim/{job_id}/segments",
  "segments": [
    {
      "index": 1,
      "bgm_key": "projects/123/interim/{job_id}/segments/0001_bgm.wav",
      "tts_key": "projects/123/interim/{job_id}/segments/0001_tts.wav",
      "output_key": "projects/123/interim/{job_id}/segments/0001_mix.wav",
      "bgm_gain": 0.35,
      "tts_gain": 1.0
    }
  ]
}
```

## 환경 변수

- `JOB_QUEUE_URL` : SQS 큐 URL
- `AWS_S3_BUCKET` : 작업 파일을 저장할 S3 버킷
- `JOB_RESULT_VIDEO_PREFIX`, `JOB_RESULT_METADATA_PREFIX` : 결과물 저장 경로 템플릿
- `JOB_TARGET_LANG`, `JOB_SOURCE_LANG` : 기본 언어 설정
- `JOB_CALLBACK_LOCALHOST_HOST` : 컨테이너 내부에서 localhost 콜백을 호출할 때 대체할 호스트명
- 그 외 `VAD_AGGR`, `VAD_FRAME_MS`, `STT_INTERVAL_MARGIN` 등 파이프라인 튜닝 옵션

## 실행 방법

### 1) Docker Compose로 로컬 GPU 워커 실행

1. 모델을 캐시하기 위한 폴더 생성

```bash
$ mkdir -p data cache/{STT, TTS}
```

2. 컨테이너에 CUDA, PyTorch 설치된 이미지를 빌드하고 띄움
   2-1. `.env`에 AWS·SQS·S3 환경 변수를 채웁니다(로컬 개발 시 IAM 자격 증명은 `~/.aws`를 컨테이너에 마운트)

```bash
$ docker compose up --build worker
```

3. 재빌드 시

```bash
$ docker compose up worker
```

### 2) Amazon ECR로 배포용 이미지 푸시

1. 리포지토리가 없다면 한 번만 생성합니다.
   ```bash
   aws ecr create-repository --repository-name stt-tts-worker
   ```
2. ECR 로그인 후 이미지를 빌드/태깅/푸시합니다.

   ```bash
   AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   REGION=ap-northeast-2
   REPO=${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/stt-tts-worker

   aws ecr get-login-password --region $REGION \
     | docker login --username AWS --password-stdin ${REPO}

   docker build -t stt-tts-worker:latest .
   docker tag stt-tts-worker:latest ${REPO}:latest
   docker push ${REPO}:latest
   ```

3. ECS/EKS/Batch 등 배포 스택에서 `${REPO}:latest` 이미지를 참조하면, CUDA와 PyTorch가 포함된 동일한 워커 이미지를 사용해 재현성 있게 배포할 수 있습니다.

워커 컨테이너는 `/app/data` 및 `/app/cache/*`에 중간 산출물을 캐시합니다. `data/` 또는 `cache/` 디렉터리를 정리하면 디스크를 확보할 수 있습니다.

## 개발 시 참고

- 새 작업 유형을 추가하려면 큐 메시지의 `task`와 필요한 필드를 정의하고, 워커에 대응 메서드를 구현한 뒤 `_handle_job`에서 분기하십시오.
- 콜백 메시지는 공유 API(`update_job_status` 등)와 호환되도록 `status`, `metadata`, `result_key`를 일관되게 유지하세요.
