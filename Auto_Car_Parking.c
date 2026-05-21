/*******************************************************************************
 * Project  : ATmega32A Autonomous Parking Robot
 * MCU      : ATmega32A @ 11.0592 MHz
 * Toolchain: avr-gcc / avr-libc
 *
 * Notes
 * ─────────────────────────────────────────────────────────────────
 * Gap OPEN/CLOSE edges require only one big delta jump (no double-confirm).
 * After front obstacle avoidance, prev_side is reset to avoid stale delta.
 * UART RX enabled — Bluetooth manual control supported (F/B/L/R/S commands).
 *******************************************************************************/

#define F_CPU 11059200UL

#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include <stdint.h>
#include <stdio.h>

/* ── Sensor pins ───────────────────────────────────────────────── */
#define REAR_TRIG    PD2
#define REAR_ECHO    PD3

#define SIDE_TRIG    PD4
#define SIDE_ECHO    PD5

#define FRONT_TRIG   PD6
#define FRONT_ECHO   PC1

/* ── Mode select ───────────────────────────────────────────────── */
#define MODE_INT_PIN          PB2
#define MANUAL_MODE_ACTIVE()  (PINB & (1 << MODE_INT_PIN))

/* ── Motor direction pins (PORTA) ──────────────────────────────── */
#define IN1  PA0
#define IN2  PA1
#define IN3  PA2
#define IN4  PA3

/* ── Manual buttons (PORTA, active LOW) ───────────────────────── */
#define BTN_FORWARD   PA4
#define BTN_BACKWARD  PA5
#define BTN_LEFT      PA6
#define BTN_RIGHT     PA7

/* ── PWM enable pins ───────────────────────────────────────────── */
#define ENA_PWM  PB3
#define ENB_PWM  PD7

/* ── UART ──────────────────────────────────────────────────────── */
#define UBRR_VAL  71

/* ── Side sensor thresholds (cm) ──────────────────────────────── */
#define SIDE_CLOSE_CM    25
#define SIDE_FAR_CM      35
#define GAP_DELTA_CM     8
#define MIN_GAP_PULSES    11

/* ── Front obstacle (cm) ───────────────────────────────────────── */
#define FRONT_STOP_CM        8
#define MAX_DIST_CM        300

/* ── Rear parking stop (cm) ────────────────────────────────────── */
#define REAR_STOP_CM        10
#define REAR_STOP_CONFIRM    2
#define REVERSE_MAX_STEPS  150

/* ── Search movement ───────────────────────────────────────────── */
#define SEARCH_SPEED     255
#define FORWARD_RUN_MS    70
#define FORWARD_STOP_MS  85

/* ── Parking movement ──────────────────────────────────────────── */
#define SPIN_KICK_SPEED  255
#define SPIN_KICK_MS     130
#define SPIN_SPEED       160
#define SPIN_MAIN_MS     250
#define REVERSE_SPEED    254
#define REVERSE_RUN_MS    50
#define REVERSE_STOP_MS  300

/* ── Manual speed ──────────────────────────────────────────────── */
#define MANUAL_SPEED  230

/* ── State machine ─────────────────────────────────────────────── */
#define STATE_IDLE          0
#define STATE_GAP_COUNTING  1
#define STATE_PARKING       2
#define STATE_DONE          3


/* ── Phase 2 reverse (into gap) ────────────────────────────────── */
#define P2_STOP_CM    10
#define P2_CONFIRM     2
#define P2_MAX_STEPS 100


/* ────────────────────────────────────────────────────────────────
 * GLOBAL STATE
 * ──────────────────────────────────────────────────────────────── */
volatile uint8_t state        = STATE_IDLE;

uint16_t prev_side      = 0;
uint8_t  gap_pulses     = 0;
uint8_t  saw_wall_first = 0;

/* ────────────────────────────────────────────────────────────────
 * SENSOR DESCRIPTOR
 * ──────────────────────────────────────────────────────────────── */
typedef struct {
    uint8_t trig;
    uint8_t echo;
    uint8_t on_portc;
} Sensor;

static Sensor REAR_SNS  = { REAR_TRIG,  REAR_ECHO,  0 };
static Sensor SIDE_SNS  = { SIDE_TRIG,  SIDE_ECHO,  0 };
static Sensor FRONT_SNS = { FRONT_TRIG, FRONT_ECHO, 1 };

void motors_stop(void);
void reset_parking_mode(void);

/* ════════════════════════════════════════════════════════════════
 * UART
 * ════════════════════════════════════════════════════════════════ */
void uart_init(void)
{
    UBRRH = 0;
    UBRRL = UBRR_VAL;
    /* ENABLE BOTH TRANSMITTER AND RECEIVER FOR BLUETOOTH */
    UCSRB = (1 << TXEN) | (1 << RXEN);
    UCSRC = (1 << URSEL) | (1 << UCSZ1) | (1 << UCSZ0);
}

void uart_putc(char c)
{
    while (!(UCSRA & (1 << UDRE)));
    UDR = c;
}

void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

/* ════════════════════════════════════════════════════════════════
 * INT2 ISR
 * ════════════════════════════════════════════════════════════════ */
ISR(INT2_vect)
{
    motors_stop();
}

/* ════════════════════════════════════════════════════════════════
 * INTERRUPTIBLE DELAY
 * ════════════════════════════════════════════════════════════════ */
void delay_ms(uint16_t ms)
{
    while (ms--)
    {
        _delay_ms(1);
        if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }
    }
}

/* ════════════════════════════════════════════════════════════════
 * PWM INIT
 * ════════════════════════════════════════════════════════════════ */
void pwm_init(void)
{
    DDRB |= (1 << ENA_PWM);     // PB3 → output (right motor enable)
    DDRD |= (1 << ENB_PWM);

TCCR0 = (1 << WGM00) | (1 << WGM01)   // Fast PWM mode
      | (1 << COM01)                    // clear OC0 on compare match → non-inverting
      | (1 << CS01)  | (1 << CS00);    // prescaler = 8

    TCCR2 = (1 << WGM20) | (1 << WGM21) | (1 << COM21) | (1 << CS22);

    OCR0 = 0;
    OCR2 = 0;
}

void set_motor_speed(uint8_t right_speed, uint8_t left_speed)
{
    OCR0 = right_speed;
    OCR2 = left_speed;
}

/* ════════════════════════════════════════════════════════════════
 * MOTOR PRIMITIVES
 * ════════════════════════════════════════════════════════════════ */
void motors_stop(void)
{
    OCR0  = 0;
    OCR2  = 0;
    PORTA &= ~((1 << IN1) | (1 << IN2) | (1 << IN3) | (1 << IN4));
}

static void right_fwd(void) { PORTA = (PORTA |  (1 << IN1)) & ~(1 << IN2); }
static void right_bwd(void) { PORTA = (PORTA |  (1 << IN2)) & ~(1 << IN1); }
static void left_fwd(void)  { PORTA = (PORTA |  (1 << IN3)) & ~(1 << IN4); }
static void left_bwd(void)  { PORTA = (PORTA |  (1 << IN4)) & ~(1 << IN3); }

void motors_forward_pwm(uint8_t speed)  { right_fwd(); left_fwd();  set_motor_speed(speed, speed); }
void motors_backward_pwm(uint8_t speed) { right_bwd(); left_bwd();  set_motor_speed(speed, speed); }
void motors_spin_left_pwm(uint8_t speed){ right_fwd(); left_bwd();  set_motor_speed(speed, speed); }
void motors_spin_right_pwm(uint8_t speed){right_bwd(); left_fwd();  set_motor_speed(speed, speed); }

void pulse_forward(uint8_t speed, uint16_t run_ms, uint16_t stop_ms)
{
    if (MANUAL_MODE_ACTIVE()) return;
    motors_forward_pwm(speed);
    delay_ms(run_ms);
    motors_stop();
    delay_ms(stop_ms);
}

void pulse_backward(uint8_t speed, uint16_t run_ms, uint16_t stop_ms)
{
    if (MANUAL_MODE_ACTIVE()) return;
    motors_backward_pwm(speed);
    delay_ms(run_ms);
    motors_stop();
    delay_ms(stop_ms);
}

void pulse_spin_left(uint8_t speed, uint16_t run_ms, uint16_t stop_ms)
{
    if (MANUAL_MODE_ACTIVE()) return;
    motors_spin_left_pwm(speed);
    delay_ms(run_ms);
    motors_stop();
    delay_ms(stop_ms);
}

/* ════════════════════════════════════════════════════════════════
 * TIMER1 INIT
 * ════════════════════════════════════════════════════════════════ */
void timer1_init(void)
{
    TCCR1A = 0x00;
    TCCR1B = 0x00;
    TCNT1  = 0;
}

/* ════════════════════════════════════════════════════════════════
 * HC-SR04
 * ════════════════════════════════════════════════════════════════ */
static uint8_t echo_high(Sensor *s)
{
    if (s->on_portc) return (PINC >> s->echo) & 1;
    else             return (PIND >> s->echo) & 1;
}

uint16_t sensor_cm(Sensor *s)
{
    uint16_t t;

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return MAX_DIST_CM; }

    PORTD &= ~(1 << s->trig);
    _delay_us(3);
    PORTD |=  (1 << s->trig);
    _delay_us(10);
    PORTD &= ~(1 << s->trig);

    TCNT1  = 0;
    TCCR1B = (1 << CS11);

    while (!echo_high(s))
    {
        if (MANUAL_MODE_ACTIVE()) { TCCR1B = 0; motors_stop(); return MAX_DIST_CM; }
        if (TCNT1 > 30000)        { TCCR1B = 0;               return MAX_DIST_CM; }
    }

    TCNT1 = 0;
    while (echo_high(s))
    {
        if (MANUAL_MODE_ACTIVE()) { TCCR1B = 0; motors_stop(); return MAX_DIST_CM; }
        if (TCNT1 > 30000)        { TCCR1B = 0;               return MAX_DIST_CM; }
    }

    t      = TCNT1;
    TCCR1B = 0;

    return (uint16_t)((uint32_t)t * 124UL / 10000UL);
}

/* ════════════════════════════════════════════════════════════════
 * MEDIAN FILTER — 5 samples
 * ════════════════════════════════════════════════════════════════ */
uint16_t sensor_filtered_cm(Sensor *s)
{
    uint16_t v[5];
    uint16_t temp;
    uint8_t  i, j;

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return MAX_DIST_CM; }

    v[0] = sensor_cm(s); delay_ms(20);
    v[1] = sensor_cm(s); delay_ms(20);
    v[2] = sensor_cm(s); delay_ms(20);
    v[3] = sensor_cm(s); delay_ms(20);
    v[4] = sensor_cm(s);

    for (i = 0; i < 5; i++)
        for (j = i + 1; j < 5; j++)
            if (v[j] < v[i])
            {
                temp = v[i]; v[i] = v[j]; v[j] = temp;
            }

    return v[2];
}

/* ════════════════════════════════════════════════════════════════
 * MANUAL OVERRIDE (WITH BLUETOOTH APP SUPPORT)
 * ════════════════════════════════════════════════════════════════ */
void manual_override_update(void)
{
    static uint8_t physical_active = 0;

    /* 1. Priority check: Physical hardware buttons */
    if (!(PINA & (1 << BTN_FORWARD)))  { motors_forward_pwm(MANUAL_SPEED); physical_active = 1; return; }
    if (!(PINA & (1 << BTN_BACKWARD))) { motors_backward_pwm(MANUAL_SPEED); physical_active = 1; return; }
    if (!(PINA & (1 << BTN_LEFT)))     { motors_spin_left_pwm(MANUAL_SPEED); physical_active = 1; return; }
    if (!(PINA & (1 << BTN_RIGHT)))    { motors_spin_right_pwm(MANUAL_SPEED); physical_active = 1; return; }

    /* 2. Stop the car if a physical button was just released */
    if (physical_active)
    {
        motors_stop();
        physical_active = 0;
    }

    /* 3. If no physical button is pressed, check Bluetooth commands */
    if (UCSRA & (1 << RXC)) 
    {
        char cmd = UDR; // Read the character from the app
        
        if      (cmd == 'F') motors_forward_pwm(MANUAL_SPEED);
        else if (cmd == 'B') motors_backward_pwm(MANUAL_SPEED);
        else if (cmd == 'L') motors_spin_left_pwm(MANUAL_SPEED);
        else if (cmd == 'R') motors_spin_right_pwm(MANUAL_SPEED);
        else if (cmd == 'S') motors_stop();
    }
}

/* ════════════════════════════════════════════════════════════════
 * RESET PARKING STATE
 * ════════════════════════════════════════════════════════════════ */
void reset_parking_mode(void)
{
    motors_stop();

    state        = STATE_IDLE;

    prev_side      = 0;
    gap_pulses     = 0;
    saw_wall_first = 0;
}
/* ════════════════════════════════════════════════════════════════
 * PARKING SEQUENCE
 * ════════════════════════════════════════════════════════════════ */
void park_car(void)
{
    uint16_t r;
    uint8_t  rear_confirm = 0;
    uint8_t  p2_confirm   = 0;
    uint8_t  i;

    state        = STATE_PARKING;
    uart_puts("[PARK] Sequence start\r\n");

    motors_stop();
    delay_ms(1500);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    /* Reverse to align with gap */
    motors_backward_pwm(200);
    delay_ms(280);
    motors_stop();
    delay_ms(300);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    /* Phase 1 — spin kick + main spin into gap */
    motors_spin_left_pwm(SPIN_KICK_SPEED);
    delay_ms(SPIN_KICK_MS);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    motors_spin_left_pwm(SPIN_SPEED);
    delay_ms(SPIN_MAIN_MS + 20);

    motors_stop();
    delay_ms(300);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    /* Phase 2 — reverse into gap until rear sensor is close */
    p2_confirm = 0;

    for (i = 0; i < P2_MAX_STEPS; i++)
    {
        if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

        r = sensor_filtered_cm(&REAR_SNS);

        if (r > 1 && r <= P2_STOP_CM) p2_confirm++;
        else                           p2_confirm = 0;

        if (p2_confirm >= P2_CONFIRM)
        {
            motors_stop();
            uart_puts("[PARK] Phase 2 — rear wall reached\r\n");
            break;
        }

        motors_backward_pwm(200);
        delay_ms(70);
        motors_stop();
        delay_ms(150);
    }

    delay_ms(300);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    /* Phase 3 — counter spin to straighten */
    motors_spin_right_pwm(SPIN_KICK_SPEED);
    delay_ms(SPIN_MAIN_MS + 110);

    motors_stop();
    delay_ms(500);

    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    /* Final reverse — push back to rear wall */
    rear_confirm = 0;

    for (i = 0; i < REVERSE_MAX_STEPS; i++)
    {
        if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

        r = sensor_filtered_cm(&REAR_SNS);

        if (r > 1 && r <= REAR_STOP_CM) rear_confirm++;
        else                             rear_confirm = 0;

        if (rear_confirm >= REAR_STOP_CONFIRM)
        {
            motors_stop();
            state     = STATE_DONE;
            uart_puts("[PARK] Done — rear wall\r\n");
            return;
        }

        motors_backward_pwm(REVERSE_SPEED);
        delay_ms(REVERSE_RUN_MS);
        motors_stop();
        delay_ms(REVERSE_STOP_MS);
    }

    motors_stop();
    state     = STATE_DONE;
    uart_puts("[PARK] Done — max steps\r\n");
}

/* ════════════════════════════════════════════════════════════════
 * AUTONOMOUS STATE MACHINE
 * ════════════════════════════════════════════════════════════════ */
void autonomous_mode(void)
{
    uint16_t s, f;
    int16_t  delta;
    char     buf[64];

    if (MANUAL_MODE_ACTIVE())                                { motors_stop(); return; }
    if (state == STATE_PARKING || state == STATE_DONE)       { motors_stop(); return; }

    /* ── Read sensors ─────────────────────────────────────────── */
    s = sensor_filtered_cm(&SIDE_SNS);
    delay_ms(10);
    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    f = sensor_filtered_cm(&FRONT_SNS);
    delay_ms(10);
    if (MANUAL_MODE_ACTIVE()) { motors_stop(); return; }

    sprintf(buf, "S=%u F=%u PREV=%u GP=%u ST=%u\r\n",
            s, f, prev_side, (uint16_t)gap_pulses, (uint16_t)state);
    uart_puts(buf);

    /* ── Front obstacle avoidance ─────────────────────────────── */
    if (f <= FRONT_STOP_CM)
    {
        uart_puts("[FRONT] Obstacle — back + spin\r\n");
        motors_stop();
        delay_ms(200);
        pulse_backward(180, 120, 200);
        pulse_spin_left(180, 150, 200);

        /* FIX 3: old reading is stale after robot moved — reset delta baseline */
        prev_side = 0;
        return;
    }

    /* ── Edge detection ───────────────────────────────────────── */
    delta = (int16_t)s - (int16_t)prev_side;

    if (state == STATE_IDLE)
    {
        /* Step 1: confirm we are driving alongside a wall */
        if (s <= SIDE_CLOSE_CM)
        {
            saw_wall_first = 1;
        }

        /* FIX 1: one big jump is enough — no double-confirm needed.
         * delta is only large at the exact moment the gap opens,
         * so requiring it twice in a row is impossible.            */
        if (saw_wall_first && s >= SIDE_FAR_CM && delta >= GAP_DELTA_CM)
        {
            gap_pulses    = 0;
            state         = STATE_GAP_COUNTING;
            uart_puts("[SM] Gap OPENED — counting\r\n");
        }
    }

    else if (state == STATE_GAP_COUNTING)
    {
        if (s >= SIDE_FAR_CM)
        {
            /* Still inside the gap — count it */
            if (gap_pulses < 255) gap_pulses++;

            sprintf(buf, "[SM] Gap pulse %u\r\n", (uint16_t)gap_pulses);
            uart_puts(buf);
        }
        /* FIX 2: one big negative jump is enough to confirm gap closed.
         * Same reason as Fix 1 — delta is only large on the first closing read. */
        else if (s <= SIDE_CLOSE_CM && delta <= -GAP_DELTA_CM)
        {
            if (gap_pulses >= MIN_GAP_PULSES)
            {
                uart_puts("[SM] Gap CLOSED — big enough, PARKING\r\n");
                motors_stop();
                delay_ms(300);
                park_car();
                return;
            }
            else
            {
                uart_puts("[SM] Gap too small — back to IDLE\r\n");
                gap_pulses     = 0;
                saw_wall_first = 1;
                state          = STATE_IDLE;
            }
        }
    }

    /* Update previous reading AFTER delta is calculated */
    prev_side = s;

    /* ── Move forward one pulse ───────────────────────────────── */
    pulse_forward(SEARCH_SPEED, FORWARD_RUN_MS, FORWARD_STOP_MS);
}

/* ════════════════════════════════════════════════════════════════
 * INTERRUPT INIT
 * ════════════════════════════════════════════════════════════════ */
void interrupt_init(void)
{
    DDRB  &= ~(1 << MODE_INT_PIN);
    PORTB &= ~(1 << MODE_INT_PIN);

    MCUCSR |= (1 << ISC2);
    GIFR   |= (1 << INTF2);
    GICR   |= (1 << INT2);

    sei();
}

/* ════════════════════════════════════════════════════════════════
 * IO INIT
 * ════════════════════════════════════════════════════════════════ */
void io_init(void)
{
    MCUCSR |= (1 << JTD);
    MCUCSR |= (1 << JTD);

    DDRD |= (1 << REAR_TRIG) | (1 << SIDE_TRIG) | (1 << FRONT_TRIG);

    DDRD &= ~((1 << REAR_ECHO) | (1 << SIDE_ECHO));
    DDRC &= ~(1 << FRONT_ECHO);

    DDRA |= (1 << IN1) | (1 << IN2) | (1 << IN3) | (1 << IN4);

    DDRA  &= ~((1 << BTN_FORWARD) | (1 << BTN_BACKWARD) |
               (1 << BTN_LEFT)    | (1 << BTN_RIGHT));
    PORTA |=   (1 << BTN_FORWARD) | (1 << BTN_BACKWARD) |
               (1 << BTN_LEFT)    | (1 << BTN_RIGHT);

    motors_stop();
}

/* ════════════════════════════════════════════════════════════════
 * MAIN
 * ════════════════════════════════════════════════════════════════ */
int main(void)
{
    uint8_t was_in_manual = 0;

    io_init();
    timer1_init();
    pwm_init();
    uart_init();
    interrupt_init();

    motors_stop();
    uart_puts("=== Parking Robot Ready ===\r\n");

    delay_ms(5000);
    reset_parking_mode();

    while (1)
    {
        if (MANUAL_MODE_ACTIVE())
        {
            if (!was_in_manual)
            {
                uart_puts("[MODE] Manual\r\n");
                was_in_manual = 1;
            }
            manual_override_update();
        }
        else
        {
            if (was_in_manual)
            {
                uart_puts("[MODE] Autonomous\r\n");
                motors_stop();
                reset_parking_mode();
                was_in_manual = 0;
            }
            autonomous_mode();
        }
    }
}