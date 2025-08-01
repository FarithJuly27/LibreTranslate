FROM python:3.11.11-slim-bullseye AS builder

WORKDIR /app

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
  && apt-get -qqq install --no-install-recommends -y pkg-config gcc g++ \
  && apt-get upgrade --assume-yes \
  && apt-get clean \
  && rm -rf /var/lib/apt

RUN python -m venv venv && ./venv/bin/pip install --no-cache-dir --upgrade pip

COPY . .

# Install package from source code, compile translations
RUN ./venv/bin/pip install Babel==2.12.1 && ./venv/bin/python scripts/compile_locales.py \
  && ./venv/bin/pip install torch==2.2.0 --extra-index-url https://download.pytorch.org/whl/cpu \
  && ./venv/bin/pip install "numpy<2" \
  && ./venv/bin/pip install . \
  && ./venv/bin/pip cache purge

# Final lightweight image
FROM python:3.11.11-slim-bullseye

ARG with_models=false
ARG models=""

RUN addgroup --system --gid 1032 libretranslate \
  && adduser --system --uid 1032 libretranslate \
  && mkdir -p /home/libretranslate/.local \
  && chown -R libretranslate:libretranslate /home/libretranslate/.local

USER libretranslate

COPY --from=builder --chown=1032:1032 /app /app
WORKDIR /app
COPY --from=builder --chown=1032:1032 /app/venv/bin/ltmanage /usr/bin/

RUN if [ "$with_models" = "true" ]; then \
      if [ ! -z "$models" ]; then \
        ./venv/bin/python scripts/install_models.py --load_only_lang_codes "$models"; \
      else \
        ./venv/bin/python scripts/install_models.py; \
      fi \
    fi

# Tell Render what port to scan
EXPOSE 5000

# Correct ENTRYPOINT (with fallback if PORT not set)
# ENTRYPOINT sh -c "./venv/bin/libretranslate --host 0.0.0.0 --port ${PORT:-5000}"
# ENTRYPOINT [ "./venv/bin/libretranslate", "--host", "*" ]
# Use CMD instead of ENTRYPOINT for testing
CMD ["./venv/bin/libretranslate", "--host", "0.0.0.0", "--port", "5000"]
