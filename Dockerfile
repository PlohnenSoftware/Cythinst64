FROM zamkorus/cythinst64:3.13.13

# Copy entrypoint and helper scripts into the container
COPY entrypoint.sh /entrypoint.sh
COPY cython_build.py /cython_build.py
COPY archive.sh /archive.sh

# Make the entrypoint and helper scripts executable
RUN sed -i 's/\r$//' /entrypoint.sh /cython_build.py /archive.sh \
    && chmod +x /entrypoint.sh /cython_build.py /archive.sh

# Set the container's entrypoint to the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
