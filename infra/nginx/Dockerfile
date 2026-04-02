FROM nginx:1.25-alpine

# remove default config
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf

# Note: nginx -t is skipped at build time because the upstream "app:8080"
# only exists inside the compose network at runtime, not during image build.

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
