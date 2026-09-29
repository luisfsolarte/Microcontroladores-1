; ===========================================================================
; PRÁCTICA 1 - MICROCONTROLADORES 
; Proyecto: Supervisión de temperatura con sensor LM35 y pantallas de 7 segmentos
;
; CONEXIONES DEL CIRCUITO
;   RA0  : Sensor de temperatura (LM35)
;   RA1  : Enciende la pantalla de las DECENAS
;   RC2  : Enciende la pantalla de las UNIDADES
;   RD0 - RD6 : Cables de las luces de los números (segmentos a - g)
;   RC0  : Motor del ventilador
;   RC1  : Bombillo LED de alarma
;   RB0  : Botón manual para la ALARMA
;   RB1  : Botón manual para el VENTILADOR
;   RB2  : Botón para cambiar entre grados °C y °F
    PROCESSOR 18F4550
    #include <xc.inc>

; CONFIGURACIONES BÁSICAS DEL MICROCONTROLADOR 
    config FOSC = INTOSCIO_EC   ; Usar el reloj interno del sistema
    config WDT = OFF            ; Apagar el reinicio automático de seguridad
    config LVP = OFF            ; Desactivar programación por bajo voltaje
    config PBADEN = OFF         ; Los pines de los botones inician como digitales
    config MCLRE = OFF          ; Desactiva el botón físico de reset
    config PWRT = ON            ; Esperar a que la energía se estabilice al prender

; DEFINICIONES
#define W 0
#define F 1
#define A 0

; BANDERAS 
F_MUX       equ 0       ; Turno de pantalla: 0 = Decenas, 1 = Unidades
F_FAHR      equ 1       ; Modo visual: 0 = Grados °C, 1 = Grados °F
F_ACT       equ 2       ; Aviso de que hay que actualizar los números en pantalla
F_AUTO      equ 3       ; Memoria para saber si el sistema automático ya se activó

; TIEMPOS Y LÍMITES DE TEMPERATURA
DEBOUNCE    equ 25      ; Filtro para evitar que un botón marque "doble clic"
N_MUESTREO  equ 50      ; Frecuencia de muestreo del sensor
UMBRAL_ON   equ 30      ; Si la temperatura pasa de 30°C, se prende todo
UMBRAL_OFF  equ 30      ; Si baja a 30°C, se apaga todo 

; RESERVA DE MEMORIA
    PSECT udata_acs
flags:          DS 1    ; Guarda interruptores
adc_h:          DS 1    ; Guarda parte alta de la lectura del sensor
adc_l:          DS 1    ; Guarda parte baja de la lectura del sensor
calc_h:         DS 1    ; Variables temporales para matemáticas
calc_l:         DS 1
temp_c:         DS 1    ; Temperatura final en grados centígrados
decenas:        DS 1    ; Número que va en el display izquierdo
unidades:       DS 1    ; Número que va en el display derecho
seg_dec:        DS 1    ; Luces que deben prender para las decenas
seg_uni:        DS 1    ; Luces que deben prender para las unidades
tmp_dec:        DS 1
tmp_uni:        DS 1
tmp_idx:        DS 1
cnt_muestreo:   DS 1
db0:            DS 1    ; Contadores para el filtro de los botones
db1:            DS 1
db2:            DS 1

; VECTORES DE INICIO Y EMERGENCIAS 
    PSECT resetVec,class=CODE,reloc=2,abs
    ORG 0x0000
    goto MAIN           ; Cuando se prende, va directo al programa principal

    PSECT hiIntVec,class=CODE,reloc=2,abs
    ORG 0x0008
    goto RUTINA_ISR     ; Si alguien oprime un botón, salta rápido a atenderlo

; ATENCIÓN A LOS BOTONES Y AL RELOJ (INTERRUPCIONES)
; Aquí el sistema pausa lo que está haciendo, atiende la urgencia y regresa.

    PSECT code
RUTINA_ISR:

; Si oprimieron la alarma (RB0)
CHK_INT0:
    BTFSS   INTCON, 4, A        ; Si el botón está activado
    BRA     CHK_INT1
    BTFSS   INTCON, 1, A        ; Si alguien lo presionó
    BRA     CHK_INT1
    BCF     INTCON, 1, A        ; Borra el aviso
    BCF     INTCON, 4, A        ; Bloqueo el botón para evitar doble click
    MOVLW   DEBOUNCE
    MOVWF   db0, A
    BTG     LATC, 1, A          ; Prende o apaga el LED de la alarma

; Si oprimieron el botón del ventilador (RB1)
CHK_INT1:
    BTFSS   INTCON3, 3, A       
    BRA     CHK_INT2
    BTFSS   INTCON3, 0, A       
    BRA     CHK_INT2
    BCF     INTCON3, 0, A
    BCF     INTCON3, 3, A       
    MOVLW   DEBOUNCE
    MOVWF   db1, A
    BTG     LATC, 0, A          ; Prende o apaga el motor

; Si oprimeron el botón del cambio (RB2)
CHK_INT2:
    BTFSS   INTCON3, 4, A       
    BRA     CHK_TMR0
    BTFSS   INTCON3, 1, A       
    BRA     CHK_TMR0
    BCF     INTCON3, 1, A
    BCF     INTCON3, 4, A       
    MOVLW   DEBOUNCE
    MOVWF   db2, A
    BTG     flags, F_FAHR, A    ; Cambia entre °C y °F
    BSF     flags, F_ACT, A     

; CONTROL DE LAS PANTALLAS 
CHK_TMR0:
    BTFSS   INTCON, 2, A        ; Mira si pasó el tiempo del reloj interno
    BRA     CHK_ADC
    BCF     INTCON, 2, A
    MOVLW   6                   ; Reiniciar el cronómetro
    MOVWF   TMR0L, A

    ; De esta forma: apaga todo, prepara el número y enciende solo uno 
    BCF     LATA, 1, A          ; Apagar decenas
    BCF     LATC, 2, A          ; Apagar unidades
    BTFSC   flags, F_MUX, A
    BRA     MUX_UNI
    MOVFF   seg_dec, LATD
    BSF     LATA, 1, A          ; Encender decenas
    BSF     flags, F_MUX, A
    BRA     MUX_FIN
MUX_UNI:
    MOVFF   seg_uni, LATD
    BSF     LATC, 2, A          ; Encender unidades
    BCF     flags, F_MUX, A
MUX_FIN:

    ; Liberar los botones cuando pase el tiempo de bloqueo
    MOVF    db0, F, A
    BZ      T0_REB1
    DECFSZ  db0, F, A
    BRA     T0_REB1
    BCF     INTCON, 1, A        
    BSF     INTCON, 4, A        
T0_REB1:
    MOVF    db1, F, A
    BZ      T0_REB2
    DECFSZ  db1, F, A
    BRA     T0_REB2
    BCF     INTCON3, 0, A       
    BSF     INTCON3, 3, A       
T0_REB2:
    MOVF    db2, F, A
    BZ      T0_MUESTREO
    DECFSZ  db2, F, A
    BRA     T0_MUESTREO
    BCF     INTCON3, 1, A       
    BSF     INTCON3, 4, A       

    ; Medir el sensor cada cierto tiempo para no saturar al sistema 
T0_MUESTREO:
    DECFSZ  cnt_muestreo, F, A
    BRA     CHK_ADC
    MOVLW   N_MUESTREO
    MOVWF   cnt_muestreo, A
    BSF     ADCON0, 1, A        ; Da la orden de leer la temperatura

; Si terminó de leer el botón de temperatura 
CHK_ADC:
    BTFSS   PIR1, 6, A          
    BRA     SALIR_ISR
    BCF     PIR1, 6, A
    MOVFF   ADRESH, adc_h       ; Guarda los datos del sensor
    MOVFF   ADRESL, adc_l
    BSF     flags, F_ACT, A     ; Pide actualizar la pantalla con el nuevo dato

SALIR_ISR:
    RETFIE  1                   ; Termina la urgencia y vuelve al programa normal

; CONFIGURACIÓN INICIAL DEL PROYECTO
MAIN:
    MOVLW   0x07
    MOVWF   CMCON, A            ; Apaga ciertas funciones analógicas 
    CLRF    CCP1CON, A          
    CLRF    CCP2CON, A
    CLRF    T1CON, A

    ; Fijar la velocidad del sistema a 8 MHz
    MOVLW   0x72
    MOVWF   OSCCON, A

    ; Configurar pines como Entradas o Salidas
    MOVLW   0x01                ; RA0 entrada (Sensor); RA1 salida (Pantalla)
    MOVWF   TRISA, A
    MOVLW   0xFF                ; Todo el Puerto B son entradas 
    MOVWF   TRISB, A
    CLRF    LATB, A
    CLRF    SSPCON1, A          
    CLRF    TRISC, A            ; Puerto C como salidas (Motor, Alarma, Pantalla)
    CLRF    TRISD, A            ; Puerto D como salidas (Luces de los números)
    
    ; Asegura que todo inicie apagado
    CLRF    LATA, A
    CLRF    LATC, A
    CLRF    LATD, A

    ; Limpia la memoria al iniciar
    CLRF    flags, A
    CLRF    adc_h, A
    CLRF    adc_l, A
    CLRF    temp_c, A
    CLRF    db0, A
    CLRF    db1, A
    CLRF    db2, A
    
    MOVLW   N_MUESTREO
    MOVWF   cnt_muestreo, A
    MOVLW   0x3F                ; Mostrar "00" mientras lee la primera temperatura
    MOVWF   seg_dec, A
    MOVWF   seg_uni, A

    ; Configurar el conversor que lee el sensor 
    MOVLW   0x0E                ; Solo el pin AN0 será analógico
    MOVWF   ADCON1, A
    MOVLW   0x92                ; Precisión y velocidad de lectura
    MOVWF   ADCON2, A
    MOVLW   0x01                ; Prende el conversor
    MOVWF   ADCON0, A

    ; Configurar el cronómetro interno para el parpadeo de las pantallas
    MOVLW   0xC5
    MOVWF   T0CON, A
    MOVLW   6
    MOVWF   TMR0L, A

    ; Activar la vigilancia de los botones
    BCF     RCON, 7, A          
    CLRF    INTCON2, A          ; Activa resistencias internas para los botones
    CLRF    INTCON3, A          
    CLRF    PIR1, A
    MOVLW   0x40
    MOVWF   PIE1, A             
    MOVLW   0x18
    MOVWF   INTCON3, A          
    MOVLW   0xF0                
    MOVWF   INTCON, A           ; Dar permiso general para interrumpir

; BUCLE INFINITO (El trabajo de rutina)

MAIN_LOOP:
    BTFSS   flags, F_ACT, A     ; Si hay temperatura nueva para procesar
    BRA     MAIN_LOOP           ; Si no, sigue esperando
    BCF     flags, F_ACT, A     ; Si sí, borra el aviso
    CALL    LEER_TEMPERATURA    ; Convierte el voltaje en grados reales
    CALL    CONTROL_TERMICO     ; Revisa si hace calor para prender el ventilador
    CALL    ARMAR_DISPLAY       ; Actualiza los números de la pantalla
    BRA     MAIN_LOOP           ; Vuelve a empezar

; FUNCIONES SECUNDARIAS MATEMÁTICAS Y DE LÓGICA

; Función para transformar el voltaje crudo del sensor a grados centígrados reales
LEER_TEMPERATURA:
    BCF     INTCON, 7, A       ; Evitar interrupciones mientras copiamos los datos
    MOVFF   adc_h, calc_h
    MOVFF   adc_l, calc_l
    BSF     INTCON, 7, A
    MOVF    calc_h, W, A
    SUBLW   1                   
    BNC     SATURA_T            ; Si la lectura es un error, poner al máximo
    MOVLW   125
    MULWF   calc_l, A           ; Matemática de conversión
    MOVLW   128
    ADDWF   PRODL, F, A         
    MOVLW   0
    ADDWFC  PRODH, W, A         
    MOVWF   temp_c, A           ; Guardar el resultado final
    MOVLW   125
    BTFSC   calc_h, 0, A        
    ADDWF   temp_c, F, A
    RETURN
SATURA_T:
    MOVLW   255                 ; Límite de seguridad en caso de fallo
    MOVWF   temp_c, A
    RETURN

; Revisa la temperatura y toma decisiones automáticas
CONTROL_TERMICO:
    BTFSC   flags, F_AUTO, A    ; Pregunta si el sistema ya está activo
    BRA     AUTO_ACTIVO         ; Sí, vamos a ver si ya se puede apagar
    MOVLW   UMBRAL_ON
    CPFSGT  temp_c, A           ; Si la temperatura pasó los 30° ; 
    RETURN                      ; No, todo está normal
    BSF     flags, F_AUTO, A    ; Sí, marcar que se activó la emergencia
    BSF     LATC, 0, A          ; Prender el ventilador
    BSF     LATC, 1, A          ; Prender la alarma
    RETURN
AUTO_ACTIVO:
    MOVLW   UMBRAL_OFF
    CPFSLT  temp_c, A           ; Pregunta si la temperatura ya bajó 28°
    RETURN                      ; No, seguir enfriando
    BCF     flags, F_AUTO, A    ; Sí, marcar que ya estamos a salvo
    BCF     LATC, 0, A          ; Apagar el ventilador
    BCF     LATC, 1, A          ; Apagar la alarma
    RETURN

; Fórmula matemática para convertir de grados Celsius a Fahrenheit
CALC_F:
    MOVLW   60
    CPFSGT  temp_c, A
    BRA     CALC_F_OK
    MOVLW   255
    RETURN
CALC_F_OK:
    MOVLW   205
    MULWF   temp_c, A           
    MOVLW   128
    ADDWF   PRODL, F, A         
    MOVF    temp_c, W, A        
    ADDWFC  PRODH, W, A         
    ADDLW   32
    RETURN

; Decide qué mostrar en pantalla y lo dibuja
ARMAR_DISPLAY:
    MOVF    temp_c, W, A
    BTFSC   flags, F_FAHR, A    ; Revisa el botón de cambio
    CALL    CALC_F              ; Si está en Fahrenheit, convierte el número
    CALL    BIN_A_BCD           ; Separa el número de 2 cifras
    MOVF    decenas, W, A
    CALL    BUSCAR_SEG          ; Busca qué luces encender para el primer dígito
    MOVWF   tmp_dec, A
    MOVF    unidades, W, A
    CALL    BUSCAR_SEG          ; Busca qué luces encender para el segundo dígito
    MOVWF   tmp_uni, A
    BCF     INTCON, 7, A        ; Pausar alertas para actualizar de forma segura
    MOVFF   tmp_dec, seg_dec
    MOVFF   tmp_uni, seg_uni
    BSF     INTCON, 7, A
    RETURN

; Función para separar el número entero en decenas y unidades (Por ejemplo 32: 3 y 2)
BIN_A_BCD:
    MOVWF   unidades, A
    CLRF    decenas, A
    MOVLW   100
    CPFSLT  unidades, A         ; Si pasa de 100, no lo podemos mostrar en 2 pantallas
    BRA     BCD_SATURA
BCD_LOOP:
    MOVLW   10
    CPFSLT  unidades, A         
    BRA     BCD_RESTA
    RETURN
BCD_RESTA:
    MOVLW   10
    SUBWF   unidades, F, A      ; Le restamos 10 a las unidades
    INCF    decenas, F, A       ; Le sumamos 1 a las decenas
    BRA     BCD_LOOP
BCD_SATURA:
    MOVLW   9
    MOVWF   decenas, A          ; Si es un error, muestra 99
    MOVWF   unidades, A
    RETURN

; "Traductor" para saber qué cables encender según el número que se pida
BUSCAR_SEG:
    MOVWF   tmp_idx, A
    MOVLW   low(TABLA_SEG)
    MOVWF   TBLPTRL, A
    MOVLW   high(TABLA_SEG)
    MOVWF   TBLPTRH, A
    CLRF    TBLPTRU, A
    MOVF    tmp_idx, W, A
    ADDWF   TBLPTRL, F, A
    MOVLW   0
    ADDWFC  TBLPTRH, F, A
    TBLRD*
    MOVF    TABLAT, W, A
    RETURN

; Mapa de dibujo de los números del 0 al 9 para los displays
TABLA_SEG:                      
    DB 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

    END