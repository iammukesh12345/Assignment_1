
# Stage 1: Build the Go application
FROM golang:1.24-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o employee-api .

# Stage 2: Run the application
FROM alpine:3.21

RUN apk add --no-cache ca-certificates \
    && addgroup -S appgroup \
    && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/employee-api .

USER appuser

EXPOSE 8080

CMD ["./employee-api"]
