FROM zamkorus/cythinst64:3.14.5

# Copy entrypoint and Cython build scripts into the container
COPY entrypoint.sh /entrypoint.sh
COPY cython_build.py /cython_build.py

# Make the entrypoint and build scripts executable
RUN sed -i 's/\r$//' /entrypoint.sh /cython_build.py \
    && chmod +x /entrypoint.sh /cython_build.py

# Set the container's entrypoint to the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
