FROM tomcat:9.0
RUN apt-get update && apt-get install -y maven

COPY bodgeit /app
WORKDIR /app

RUN mvn clean package
RUN cp target/*.war /usr/local/tomcat/webapps/bodgeit.war
