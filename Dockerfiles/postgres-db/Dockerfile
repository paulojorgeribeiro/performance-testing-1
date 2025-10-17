FROM postgres:latest

# Set environment variables (you can also use a .env file with docker-compose)
ENV POSTGRES_USER=admin
ENV POSTGRES_PASSWORD=adminpass
ENV POSTGRES_DB=performance_testing

# Copy initialization script into the container
COPY init-db.sql /docker-entrypoint-initdb.d/
RUN chmod 644 /docker-entrypoint-initdb.d/init-db.sql \
 && chown postgres:postgres /docker-entrypoint-initdb.d/init-db.sql