FROM zamkorus/cythinst64:3.13.13

# Copy entrypoint and Cython build scripts into the container
COPY entrypoint.sh /entrypoint.sh
COPY cython_build.py /cython_build.py
COPY zip_package.py /zip_package.py

# Make the entrypoint and build scripts executable
RUN sed -i 's/\r$//' /entrypoint.sh /cython_build.py /zip_package.py \
    && chmod +x /entrypoint.sh /cython_build.py /zip_package.py

# Set the container's entrypoint to the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
