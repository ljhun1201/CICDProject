# Java 17
FROM openjdk:17

# 작업 디렉토리 설정
WORKDIR /app

# 빌드된 JAR 복사
COPY build/libs/*.jar app.jar

# 포트 노출 (Spring Boot default)
EXPOSE 8080

# 환경변수에 따라 Spring이 DB 접속정보 주입 가능하도록 설정
ENTRYPOINT ["java", "-jar", "app.jar"]
