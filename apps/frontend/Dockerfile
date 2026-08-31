# ==============================================================================
# Production Dockerfile for Ticket System Frontend (Hardened Nginx SPA Proxy)
# ==============================================================================

FROM nginx:1.25-alpine

# Install curl for reliable health checks
RUN apk add --no-cache curl

# Remove default boilerplate configuration
RUN rm -rf /etc/nginx/conf.d/* /usr/share/nginx/html/*

# Copy custom Nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static frontend SPA assets
COPY src/ /usr/share/nginx/html/

# Set proper read permissions
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]

