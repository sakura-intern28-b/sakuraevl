package telemetry
import "context"
func Init(ctx context.Context) (func(context.Context) error, error) { return func(context.Context) error { return nil }, nil }
