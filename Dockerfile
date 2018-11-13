# Base image
FROM nginx

# Remove the default Nginx configuration file
RUN rm -v /etc/nginx/nginx.conf

# Copy a configuration file from the current directory
ADD /nginx-proxy/nginx.conf /etc/nginx/

# Copy sites-available
RUN mkdir /etc/nginx/sites-enabled
COPY nginx-proxy/sites-available/* /etc/nginx/sites-enabled/

# Expose the port the app runs in
EXPOSE 80