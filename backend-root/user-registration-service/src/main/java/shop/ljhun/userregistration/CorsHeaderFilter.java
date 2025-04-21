package shop.ljhun.userregistration;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;

import java.io.IOException;

// ✅ @Component: Spring이 이 클래스를 Bean으로 자동 등록하도록 지시하는 애너테이션
// - 클래스 단위로 적용됨 (즉, 이 클래스 전체가 Bean으로 등록됨)
// - 스프링 부트가 실행되면 Component Scan을 통해 이 클래스를 찾아 자동으로 DI 컨테이너에 넣음
// - Servlet Filter로 동작하게 하기 위해 @Component로 등록하면 Spring이 자동으로 필터 체인에 연결해줌

// @Component를 사용한다면?
// ✅ 자동 등록:	Spring Boot가 이 클래스를 서블릿 필터로 자동 등록해줌. 별도의 설정 필요 없음.
// ✅ FilterChain에 자동 포함:	Spring의 DispatcherServlet 앞단 필터 체인에 자동 포함됨.
// ✅ Spring Context 관리 대상:	다른 Bean 주입(@Autowired)도 가능함.

// @Component를 사용한다면?
// ❌ 등록 안 됨	Spring은 이 클래스를 모름. 필터로 사용되지 않음.
// ❌ 요청 가로채지 않음	doFilter()가 호출되지 않음, 즉 요청을 가로채지 않음.
// ⛔ 해결 방법 필요	수동으로 FilterRegistrationBean을 통해 명시적으로 등록해야 함.

@Component
public class CorsHeaderFilter implements Filter {

    // ✅ doFilter: 모든 HTTP 요청이 Controller에 도달하기 전에 이 메서드를 거침
    // - Servlet Filter 인터페이스의 핵심 메서드
    // - 요청(Request)과 응답(Response)을 가로채서 가공하거나 조건에 따라 차단, 로깅 등을 할 수 있음

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletResponse res = (HttpServletResponse) response;
        String origin = ((jakarta.servlet.http.HttpServletRequest) request).getHeader("Origin");

        // 허용할 도메인 목록
        if ("https://www.ljhun.shop".equals(origin) || "https://ljhun.shop".equals(origin)) {
            res.setHeader("Access-Control-Allow-Origin", origin); // 요청 Origin을 그대로 echo
            res.setHeader("Access-Control-Allow-Credentials", "true");
            res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
            res.setHeader("Access-Control-Allow-Headers", "content-type, authorization");
            res.setHeader("Vary", "Origin");
        }

        chain.doFilter(request, response); //처리한 요청에 대해 다음단계로 자동 진행
    }
}