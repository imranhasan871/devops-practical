FROM nginx:1.25-alpine

# remove default config
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf

# validate config at build time so bad configs fail fast
RUN nginx -t

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
