import serial
import matplotlib.pyplot as plt
import pandas as pd
import time

# Configure serial port
port = 'COM3'  # Change to your ESP32's COM port
baud = 115200

def collect_data():
    ser = serial.Serial(port, baud)
    print("Connected to ESP32, starting test...")
    
    # Wait for header
    while True:
        line = ser.readline().decode('utf-8').strip()
        if "PWM,RPM" in line:
            break
    
    # Collect data
    data = []
    while True:
        line = ser.readline().decode('utf-8').strip()
        if "Test complete" in line:
            break
        try:
            values = [float(x) for x in line.split(',')]
            data.append(values)
        except:
            continue
    
    ser.close()
    return pd.DataFrame(data, columns=['PWM', 'RPM', 'Torque', 'Current', 'Voltage',
                                    'MechanicalPower', 'ElectricalPower', 'Efficiency'])

def plot_results(df):
    plt.figure(figsize=(15, 10))
    
    plt.subplot(2, 2, 1)
    plt.plot(df['RPM'], df['Efficiency'], 'bo-')
    plt.xlabel('RPM')
    plt.ylabel('Efficiency (%)')
    plt.title('Efficiency vs. RPM')
    plt.grid(True)
    
    plt.subplot(2, 2, 2)
    plt.plot(df['Torque'], df['Efficiency'], 'ro-')
    plt.xlabel('Torque (Nm)')
    plt.ylabel('Efficiency (%)')
    plt.title('Efficiency vs. Torque')
    plt.grid(True)
    
    plt.subplot(2, 2, 3)
    plt.plot(df['PWM'], df['RPM'], 'go-')
    plt.xlabel('PWM')
    plt.ylabel('RPM')
    plt.title('Speed vs. PWM')
    plt.grid(True)
    
    plt.subplot(2, 2, 4)
    plt.plot(df['Current'], df['Torque'], 'mo-')
    plt.xlabel('Current (A)')
    plt.ylabel('Torque (Nm)')
    plt.title('Torque vs. Current')
    plt.grid(True)
    
    plt.tight_layout()
    plt.savefig('motor_efficiency_results.png')
    plt.show()
    
    # Save to CSV
    df.to_csv('motor_efficiency_data.csv', index=False)

if __name__ == "__main__":
    df = collect_data()
    plot_results(df)
    print("Analysis complete!")