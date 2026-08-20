// Package telemetry は OTLP/HTTP 経由でトレースを送信するための初期化処理を提供する。
package telemetry

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.43.0"
)

// noop はトレース送信を行わない場合に使うシャットダウン関数。
func noop(context.Context) error { return nil }

// Init はグローバルな TracerProvider を初期化する。
// OTEL_EXPORTER_OTLP_TRACES_ENDPOINT が未設定の場合は何もせずトレースを無効化する。
func Init(ctx context.Context) (func(context.Context) error, error) {
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
	if endpoint == "" {
		return noop, nil
	}

	u, err := url.Parse(endpoint)
	if err != nil {
		return noop, fmt.Errorf("parse OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: %w", err)
	}

	opts := []otlptracehttp.Option{
		otlptracehttp.WithEndpoint(u.Host),
		otlptracehttp.WithURLPath(u.Path),
	}
	if u.Scheme != "https" {
		opts = append(opts, otlptracehttp.WithInsecure())
	}

	exporter, err := otlptracehttp.New(ctx, opts...)
	if err != nil {
		return noop, fmt.Errorf("create otlp trace exporter: %w", err)
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "sakuravel-api"
	}

	// WithFromEnv により OTEL_RESOURCE_ATTRIBUTES を取り込む。
	// 性能比較時に service.version=<イメージのタグ> を付けて
	// 同一サービスの新旧を区別できるようにするため。
	// 後続の WithAttributes が環境変数より優先される。
	res, err := resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithAttributes(semconv.ServiceName(serviceName)),
		resource.WithAttributes(deployEnvAttributes()...),
		resource.WithAttributes(serviceVersionAttributes()...),
	)
	if err != nil {
		return noop, fmt.Errorf("create resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp.Shutdown, nil
}

// serviceVersionAttributes は service.version を <タグ>-<コミットSHA> に合成する。
// タグ (latest / baseline 等) は可変で後から指す実体が変わるため、
// ビルド時にイメージへ焼き込まれた APP_GIT_SHA を必ず含めることで、
// トレースをコミット単位で一意に区別できるようにする。
// APP_GIT_SHA を持たない古いイメージでは何もせず、
// OTEL_RESOURCE_ATTRIBUTES 由来のタグのみの値にフォールバックする。
func serviceVersionAttributes() []attribute.KeyValue {
	sha := strings.TrimSpace(os.Getenv("APP_GIT_SHA"))
	if sha == "" || sha == "unknown" {
		return nil
	}
	version := sha
	if tag := strings.TrimSpace(os.Getenv("BACKEND_TAG")); tag != "" {
		version = tag + "-" + sha
	}
	return []attribute.KeyValue{semconv.ServiceVersion(version)}
}

func deployEnvAttributes() []attribute.KeyValue {
	env := strings.TrimSpace(os.Getenv("DEPLOY_ENV"))
	if env == "" {
		return nil
	}
	return []attribute.KeyValue{semconv.DeploymentEnvironmentNameKey.String(env)}
}
