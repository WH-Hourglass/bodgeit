# Build via:
# docker build --no-cache -t psiinon/bodgeit -f Dockerfile .
# Run via:
# docker run --rm -p 8080:8080 -i -t psiinon/bodgeit

FROM tomcat:9.0
MAINTAINER Simon Bennetts "psiinon@gmail.com"

COPY bodgeit.war /usr/local/tomcat/webapps/bodgeit.war

EXPOSE 8080

CMD ["catalina.sh", "run"]

