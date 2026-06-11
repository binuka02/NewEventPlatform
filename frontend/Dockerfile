# Use lightweight nginx to serve the HTML
FROM nginx:alpine

# Copy all frontend files into nginx's web root
COPY . /usr/share/nginx/html

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]